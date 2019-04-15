-module(aestratum_client_session).

-export([new/1,
         handle_event/2,
         close/1
        ]).

-ifdef(TEST).
-export([state/1]).
-endif.

-record(state, {
          phase,
          req_id = 0,
          reqs = maps:new(),   %% cache of sent requests
          host,
          port,
          user,
          extra_nonce,
          target
        }).

-define(DEBUG(Fmt, Args), aestratum_client:debug(Fmt, Args)).
-define(INFO(Fmt, Args), aestratum_client:info(Fmt, Args)).
-define(ERROR(Fmt, Args), aestratum_client:error(Fmt, Args)).
-define(WARN(Fmt, Args), aestratum_client:warning(Fmt, Args)).
-define(CRITICAL(Fmt, Args), aestratum_client:critical(Fmt, Args)).

-define(USER_AGENT, <<"aeclient/1.0.0">>). %% TODO: get version programatically
-define(MAX_RETRIES, application:get_env(aestratum, max_retries, 3)).
-define(MSG_TIMEOUT, application:get_env(aestratum, timeout, 30000)).

%% API.

new(#{host := Host, port := Port, user := User, password := null}) ->
    #state{phase = connected, host = Host, port = Port, user = User}.

handle_event({conn, What}, State)  ->
    handle_conn_event(What, State);
handle_event({miner, What}, State) ->
    handle_miner_event(What, State).

close(State) ->
    close_session(State),
    ok.

%% Internal functions.

handle_conn_event(#{event := init}, #state{phase = connected} = State) ->
    send_req(configure, 0, State);
handle_conn_event(#{event := recv_data, data := RawMsg}, State) ->
    case aestratum_jsonrpc:decode(RawMsg) of
        {ok, Msg}    -> recv_msg(Msg, State);
        {error, Rsn} -> recv_msg_error(Rsn, State)
    end;
%% TODO: {reconnect, Host, Port, WaitTime},...
handle_conn_event(#{event := timeout, id := Id}, #state{reqs = Reqs} = State) ->
    TimeoutInfo = find_req(Id, Reqs),
    handle_conn_timeout(Id, TimeoutInfo, State);
handle_conn_event(#{event := close}, State) ->
    {stop, close_session(State)}.

handle_miner_event(#{event := found_share} = FoundShareEvent, State) ->
    handle_miner_found_share(FoundShareEvent, State).

%% Handle received messages.

recv_msg(#{type := rsp, id := Id} = Rsp, #state{reqs = Reqs} = State) ->
    case find_req(Id, Reqs) of
        #{req := #{method := Method}} ->
            %% Received response with correct Id.
            case aestratum_jsonrpc:validate_rsp(Method, Rsp) of
                {ok, Rsp1} ->
                    %% Response validation success. The request to which the
                    %% response was sent is deleted from the sent requests and
                    %% timer is cancelled, too.
                    recv_rsp(Rsp1, State#state{reqs = del_req(Id, Reqs)});
                {error, Rsn} ->
                    %% Response validation error.
                    recv_msg_error(Rsn, State)
            end;
        not_found ->
            %% Received unexpected response (no matching Id in sent requests).
            ?ERROR("recv_rsp, reason: ~p", [req_id_not_found]),
            {no_send, State}
    end;
recv_msg(#{type := ntf} = Ntf, State) ->
    recv_ntf(Ntf, State);
recv_msg(#{type := req, method := reconnect} = Req, State) ->
    ?ERROR("recv_msg, reason: ~p", [reconnect_not_implemented]),
    {no_send, State}.

%% Handle decoded (without error) message from server.

recv_rsp(#{method := configure, result := []} = Rsp,
          #state{phase = connected} = State) ->
    %% TODO: configure has no params (yet).
    ?INFO("recv_configure_rsp, rsp: ~p", [Rsp]),
    send_req(subscribe, 0, State#state{phase = configured});
recv_rsp(#{method := subscribe, result := [SessionId, ExtraNonce]} = Rsp,
          #state{phase = configured} = State) ->
    ?INFO("recv_subscribe_rsp, rsp: ~p", [Rsp]),
    %% TODO: save SessionId(?)
    NBytes = byte_size(ExtraNonce) div 2,
    ExtraNonce1 = aestratum_nonce:to_int(extra, ExtraNonce, NBytes),
    ExtraNonce2 = aestratum_nonce:new(extra, ExtraNonce1, NBytes),
    send_req(authorize, 0, State#state{phase = subscribed,
                                       extra_nonce = ExtraNonce2});
recv_rsp(#{method := authorize, result := true} = Rsp,
          #state{phase = subscribed} = State) ->
    ?INFO("recv_authorize_rsp, rsp: ~p", [Rsp]),
    {no_send, State#state{phase = authorized}};
recv_rsp(#{method := authorize, result := false} = Rsp,
          #state{phase = subscribed} = State) ->
    ?INFO("recv_authorize_rsp, rsp: ~p", [Rsp]),
    {stop, close_session(State)};
recv_rsp(#{method := submit, result := true} = Rsp,
          #state{phase = authorized} = State) ->
    ?INFO("recv_submit_rsp, rsp: ~p", [Rsp]),
    {no_send, State};
recv_rsp(#{method := submit, result := false} = Rsp,
          #state{phase = authorized} = State) ->
    ?INFO("recv_submit_rsp, rsp: ~p", [Rsp]),
    {no_send, State};
recv_rsp(#{method := Method, reason := Rsn, msg := ErrMsg,
           data := ErrData} = Rsp, State) ->
    ?ERROR("recv_error_rsp, rsp: ~p", [Rsp]),
    %% TODO: maybe retry
    {no_send, State}.

recv_ntf(#{method := set_target, target := Target} = Ntf,
         #state{phase = authorized} = State) ->
    ?INFO("recv_set_target_ntf, ntf: ~p", [Ntf]),
    {no_send, State#state{target = aestratum_target:to_int(Target)}};
recv_ntf(#{method := notify, job_id := JobId, block_version := Blockversion,
           block_hash := BlockHash, empty_queue := EmptyQueue} = Ntf,
         #state{phase = authorized, extra_nonce = ExtraNonce,
                target = Target} = State) ->
    ?INFO("recv_notify_ntf, ntf: ~p", [Ntf]),
    Job = maps:without([method], Ntf),
    Job1 = Job#{target => Target},
    case aestratum_client_generator_manager:generate(Job1, ExtraNonce) of
        {ok, #{started := {StartedWorkers, StartedNonces},
               queued := {QueuedWorkers, QueuedNonces}}} ->
            ?INFO("generate, started_workers: ~p, started_nonces: ~p, "
                  "queued_workers: ~p, queued_nonces: ~p",
                  [StartedWorkers, StartedNonces, QueuedWorkers, QueuedNonces]);
        {error, Rsn} ->
            ?WARN("generate, reason: ~p", [Rsn])
    end,
    {no_send, State};
recv_ntf(Ntf, State) ->
    ?ERROR("recv_ntf, ntf: ~p", [Ntf]),
    {no_send, State}.

%% Handle badly encoded/invalid messages from server.

recv_msg_error(parse_error = Rsn, State) ->
    ?ERROR("recv_msg_error, reason: ~p", [Rsn]),
    {stop, close_session(State)};
recv_msg_error({invalid_msg = Rsn, MaybeId}, State) ->
    ?ERROR("recv_msg_error, reason: ~p, id: ~p", [Rsn, MaybeId]),
    {stop, close_session(State)};
recv_msg_error({invalid_method = Rsn, MaybeId}, State) ->
    ?ERROR("recv_msg_error, reason: ~p, id: ~p", [Rsn, MaybeId]),
    {stop, close_session(State)};
recv_msg_error({invalid_param = Rsn, MaybeId, Param}, State) ->
    ?ERROR("recv_msg_error, reason: ~p, id: ~p, param: ~p",
           [Rsn, MaybeId, Param]),
    {stop, close_session(State)};
recv_msg_error({internal_error = Rsn, MaybeId}, State) ->
    ?ERROR("recv_msg_error, reason: ~p, id: ~p", [Rsn, MaybeId]),
    {stop, close_session(State)}.

%% Handle timeout.

handle_conn_timeout(Id, #{phase := connected, retries := Retries},
                    #state{phase = connected, reqs = Reqs} = State) ->
    ?INFO("handle_conn_timeout, req_id: ~p", [Id]),
    send_req(configure, Retries + 1, State#state{reqs = del_req(Id, Reqs)});
handle_conn_timeout(Id, #{phase := configured, retries := Retries},
                    #state{phase = configured, reqs = Reqs} = State) ->
    ?INFO("handle_conn_timeout, req_id: ~p", [Id]),
    send_req(subscribe, Retries + 1, State#state{reqs = del_req(Id, Reqs)});
handle_conn_timeout(Id, #{phase := subscribed, retries := Retries},
                    #state{phase = subscribed, reqs = Reqs} = State) ->
    ?INFO("handle_conn_timeout, req_id: ~p", [Id]),
    send_req(authorize, Retries + 1, State#state{reqs = del_req(Id, Reqs)});
handle_conn_timeout(Id, #{phase := authorized, retries := Retries, info := Info},
                    #state{phase = authorized, reqs = Reqs} = State) ->
    ?INFO("handle_conn_timeout, req_id: ~p", [Id]),
    send_req(submit, Info, Retries + 1, State#state{reqs = del_req(Id, Reqs)});
%% This timeout was set in one phase and got triggered when the session moved
%% to a next phase (it got triggered during phase switch). The timeout is not
%% valid anymore, there is no action required.
handle_conn_timeout(Id, #{phase := Phase},
                    #state{phase = Phase1, reqs = Reqs} = State) when
      Phase =/= Phase1 ->
    {no_send, State#state{reqs = del_req(Id, Reqs)}};
handle_conn_timeout(Id, not_found, State) ->
    ?ERROR("handle_conn_timeout, reason: ~p, req_id: ~p",
           [unexpected_timeout, Id]),
    {no_send, State}.

%% Client to server requests.

send_req(ReqType, Retries, State) ->
    case Retries > ?MAX_RETRIES of
        true ->
            ?WARN("send_req aborted, reason: ~p", [max_retries_exhausted]),
            {stop, close_session(State)};
        false ->
            case ReqType of
                configure -> send_configure_req(Retries, State);
                subscribe -> send_subscribe_req(Retries, State);
                authorize -> send_authorize_req(Retries, State)
            end
    end.

send_req(submit, Info, Retries, State) ->
    %% TODO: submit request is sent just once, no retries?
    case Retries >= 1 of
        true  -> {no_send, State};
        false -> send_submit_req(Info, Retries, State)
    end.

send_configure_req(Retries, #state{req_id = Id, reqs = Reqs} = State) ->
    ReqMap = #{type => req, method => configure, id => Id, params => []},
    ?INFO("send_configure_req, req: ~p", [ReqMap]),
    {send, encode(ReqMap),
     State#state{req_id = next_id(Id),
                 reqs = add_req(Id, connected, Retries, ReqMap, Reqs)}}.

send_subscribe_req(Retries, #state{req_id = Id, reqs = Reqs,
                                   host = Host, port = Port} = State) ->
    ReqMap = #{type => req, method => subscribe, id => Id,
               user_agent => ?USER_AGENT, session_id => null, host => Host,
               port => Port},
    ?INFO("send_subscribe_req, req: ~p", [ReqMap]),
    {send, encode(ReqMap),
     State#state{req_id = next_id(Id),
                 reqs = add_req(Id, configured, Retries, ReqMap, Reqs)}}.

send_authorize_req(Retries, #state{req_id = Id, reqs = Reqs,
                                   user = User} = State) ->
    ReqMap = #{type => req, method => authorize, id => Id,
               user => User, password => null},
    ?INFO("send_authorize_req, req: ~p", [ReqMap]),
    {send, encode(ReqMap),
     State#state{req_id = next_id(Id),
                 reqs = add_req(Id, subscribed, Retries, ReqMap, Reqs)}}.

send_submit_req(#{job_id := JobId, miner_nonce := MinerNonce, pow := Pow} = Info,
                Retries, #state{req_id = Id, reqs = Reqs,
                                user = User} = State) ->
    MinerNonce1 = aestratum_nonce:to_hex(MinerNonce),
    ReqMap = #{type => req, method => submit, id => Id,
               user => User, job_id => JobId, miner_nonce => MinerNonce1,
               pow => Pow},
    ?INFO("send_submit_req, req: ~p", [ReqMap]),
    {send, encode(ReqMap),
     State#state{req_id = next_id(Id),
                 reqs = add_req(Id, authorized, Info, Retries, ReqMap, Reqs)}}.

%% Miner found share event.

handle_miner_found_share(FoundShareEvent, #state{phase = authorized} = State) ->
    FoundShare = maps:without([event], FoundShareEvent),
    ?INFO("handle_miner_found_share, found_share: ~p", [FoundShare]),
    send_req(submit, FoundShare, 0, State);
handle_miner_found_share(FoundShareEvent, State) ->
    ?ERROR("handle_miner_found_share, reason: ~p, event: ~p",
           [unexpected_miner_event, FoundShareEvent]),
    {no_send, State}.

%% Helper functions.

close_session(#state{reqs = Reqs} = State) ->
    ?CRITICAL("close_session", []),
    State#state{phase = disconnected, reqs = clean_reqs(Reqs)}.

add_req(Id, Phase, Retries, Req, Reqs) ->
    add_req(Id, Phase, undefined, Retries, Req, Reqs).

add_req(Id, Phase, Info, Retries, Req, Reqs) ->
    TimeoutEvent = #{event => timeout, id => Id},
    TRef = erlang:send_after(?MSG_TIMEOUT, self(), {conn, TimeoutEvent}),
    TimeoutInfo = #{timer => TRef, phase => Phase, info => Info,
                    retries => Retries, req => Req},
    maps:put(Id, TimeoutInfo, Reqs).

find_req(Id, Reqs) ->
    maps:get(Id, Reqs, not_found).

del_req(Id, Reqs) ->
    case maps:get(Id, Reqs, not_found) of
        #{timer := TRef} ->
            erlang:cancel_timer(TRef),
            maps:remove(Id, Reqs);
        not_found ->
            Reqs
    end.

clean_reqs(Reqs) ->
    lists:foreach(fun({_Id, #{timer := TRef}}) ->
                          erlang:cancel_timer(TRef)
                  end, maps:to_list(Reqs)),
    maps:new().

next_id(Id) ->
    aestratum_jsonrpc:next_id(Id).

encode(Map) ->
    {ok, RawMsg} = aestratum_jsonrpc:encode(Map),
    RawMsg.

%% Used for testing.

-ifdef(TEST).
state(#state{phase = Phase, req_id = ReqId, reqs = Reqs,
             extra_nonce = ExtraNonce, target = Target}) ->
    Target1 =
        case Target of
            T when T =/= undefined ->
                aestratum_target:to_hex(T);
            undefined ->
                undefined
        end,
    #{phase       => Phase,
      req_id      => ReqId,
      reqs        => maps:map(fun(Id, #{phase := Phase}) -> Phase end, Reqs),
      extra_nonce => ExtraNonce,
      target      => Target1
     }.
-endif.

