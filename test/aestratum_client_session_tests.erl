-module(aestratum_client_session_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEST_MODULE, aestratum_client_session).
-define(JSONRPC_MODULE, aestratum_jsonrpc).
-define(NONCE_MODULE, aestratum_nonce).
-define(CLIENT_GENERATOR_MANAGER_MODULE, aestratum_client_generator_manager).

-define(TEST_ACCOUNT, <<"ak_DummyPubKeyDoNotEverUse999999999999999999999999999">>).
-define(TEST_WORKER, <<"worker1">>).
-define(TEST_USER, {?TEST_ACCOUNT, ?TEST_WORKER}).

-define(TEST_TARGET,
        <<"0000ff0000000000000000000000000000000000000000000000000000000000">>).
-define(TEST_JOB_ID, <<"0102030405060708">>).
-define(TEST_BLOCK_HASH,
        <<"000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f">>).
-define(TEST_POW, lists:seq(1, 42)).

session_test_() ->
    {setup,
     fun() ->
             {ok, Apps} = application:ensure_all_started(aestratum_lib),
             meck:new(?CLIENT_GENERATOR_MANAGER_MODULE, [passthrough]),
             Apps
     end,
     fun(Apps) ->
             meck:unload(?CLIENT_GENERATOR_MANAGER_MODULE),
             lists:foreach(fun(App) -> application:stop(App) end, Apps)
     end,
     [{generator, fun client_session/0}]}.

client_session() ->
    {foreach,
     fun() ->
             SessionOpts =
                #{host => <<"pool.aeternity.com">>,
                  port => 9999,
                  account => ?TEST_ACCOUNT,
                  worker => ?TEST_WORKER,
                  password => null},
             {ok, Pid} = aestratum_dummy_handler:start_link(?TEST_MODULE, SessionOpts),
             Pid
     end,
     fun(Pid) ->
             aestratum_dummy_handler:stop(Pid)
     end,
     [fun(Pid) -> t(Pid, init()) end,
      %% connected - error
      fun(Pid) -> t(Pid, when_connected(timeout_0_retries)) end,
      fun(Pid) -> t(Pid, when_connected(timeout_1_retries)) end,
      fun(Pid) -> t(Pid, when_connected(jsonrpc_rsp_parse_error)) end,
      fun(Pid) -> t(Pid, when_connected(jsonrpc_rsp_invalid_msg)) end,
      fun(Pid) -> t(Pid, when_connected(jsonrpc_rsp_invalid_method)) end,
      fun(Pid) -> t(Pid, when_connected(jsonrpc_rsp_invalid_param)) end,
      fun(Pid) -> t(Pid, when_connected(subscribe_rsp)) end,
      fun(Pid) -> t(Pid, when_connected(authorize_rsp)) end,
      fun(Pid) -> t(Pid, when_connected(set_target_ntf)) end,
      fun(Pid) -> t(Pid, when_connected(notify_ntf)) end,
      fun(Pid) -> t(Pid, when_connected(found_share_msg)) end,
      %% connected - success
      fun(Pid) -> t(Pid, when_connected(configure_rsp)) end,

      %% configure - error
      fun(Pid) -> t(Pid, when_configured(timeout)) end,
      fun(Pid) -> t(Pid, when_configured(jsonrpc_rsp_parse_error)) end,
      fun(Pid) -> t(Pid, when_configured(jsonrpc_rsp_invalid_msg)) end,
      fun(Pid) -> t(Pid, when_configured(jsonrpc_rsp_invalid_method)) end,
      fun(Pid) -> t(Pid, when_configured(jsonrpc_rsp_invalid_param)) end,
      fun(Pid) -> t(Pid, when_configured(configure_rsp)) end,
      fun(Pid) -> t(Pid, when_configured(authorize_rsp)) end,
      fun(Pid) -> t(Pid, when_configured(set_target_ntf)) end,
      fun(Pid) -> t(Pid, when_configured(notify_ntf)) end,
      fun(Pid) -> t(Pid, when_configured(found_share_msg)) end,
      %% configure - success
      fun(Pid) -> t(Pid, when_configured(subscribe_rsp)) end,

      %% subscribe - error
      fun(Pid) -> t(Pid, when_subscribed(timeout)) end,
      fun(Pid) -> t(Pid, when_subscribed(jsonrpc_rsp_parse_error)) end,
      fun(Pid) -> t(Pid, when_subscribed(jsonrpc_rsp_invalid_msg)) end,
      fun(Pid) -> t(Pid, when_subscribed(jsonrpc_rsp_invalid_method)) end,
      fun(Pid) -> t(Pid, when_subscribed(jsonrpc_rsp_invalid_param)) end,
      fun(Pid) -> t(Pid, when_subscribed(configure_rsp)) end,
      fun(Pid) -> t(Pid, when_subscribed(subscribe_rsp)) end,
      fun(Pid) -> t(Pid, when_subscribed(authorize_failure_rsp)) end,
      fun(Pid) -> t(Pid, when_subscribed(set_target_ntf)) end,
      fun(Pid) -> t(Pid, when_subscribed(notify_ntf)) end,
      fun(Pid) -> t(Pid, when_subscribed(found_share_msg)) end,
      %% subscribe - success
      fun(Pid) -> t(Pid, when_subscribed(authorize_success_rsp)) end,

      %% authorize - error
      fun(Pid) -> t(Pid, when_authorized(timeout)) end,
      %% authorize - success
      fun(Pid) -> t(Pid, when_authorized(set_target_ntf)) end,
      fun(Pid) -> t(Pid, when_authorized(notify_ntf)) end,
      fun(Pid) -> t(Pid, when_authorized(found_share_msg)) end
      %% TODO submit_failure_rsp, submit_success_rsp, send submit and timeout
      ]}.


%% T - title
%% G - test/no_test - generate test/not generate
%% E - event
%% A - action
%% S - session state
%% R - result
t(Pid, Data) ->
    Asserts =
        [begin
            R1 = result(Pid, R, aestratum_dummy_handler:handle_event(Pid, event(E))),
            case G of
                test -> {T, ?_assertEqual(R, R1)};
                no_test -> no_test
            end
         end || {T, G, E, R} <- Data],
    lists:filter(fun({_T, _Assert}) -> true;
                    (no_test) -> false end, Asserts).

%% D - data
event({conn, D}) ->
    case maps:get(event, D, undefined) of
        E when E =/= undefined ->
            %% Map has event key, so it's an event already.
            {conn, D};
        undefined ->
            %% Map doesn't have event key, so it's a message that needs encoding.
            {ok, D1} = ?JSONRPC_MODULE:encode(D),
            {conn, #{event => recv_data, data => D1}}
    end;
event({miner, D}) ->
    %% This is an event.
    {miner, D}.

result(Pid, {_A, S}, {A1, S1}) ->
    Ks = maps:keys(S),
    S1M = maps:with(Ks, aestratum_dummy_handler:state_to_map(Pid, S1)),
    {A1, S1M};
result(Pid, {_A, S}, {A1, D1, S1}) ->
    Ks = maps:keys(S),
    S1M = maps:with(Ks, aestratum_dummy_handler:state_to_map(Pid, S1)),
    {ok, D1M} = ?JSONRPC_MODULE:decode(D1),
    {A1, D1M, S1M};
result(Pid, {_A, _D, S}, {A1, S1}) ->
    Ks = maps:keys(S),
    S1M = maps:with(Ks, aestratum_dummy_handler:state_to_map(Pid, S1)),
    {A1, S1M};
result(Pid, {_A, D, S}, {A1, D1, S1}) ->
    Ks = maps:keys(S),
    S1M = maps:with(Ks, aestratum_dummy_handler:state_to_map(Pid, S1)),
    {ok, D1M0} = ?JSONRPC_MODULE:decode(D1),
    D1M = maps:with(maps:keys(D), maybe_rsp_result(D, D1M0)),
    {A1, D1M, S1M}.

%% If type is rsp, we need to validate the result.
maybe_rsp_result(#{type := rsp, method := M}, #{type := rsp} = D1M0) ->
    {ok, D1M} = ?JSONRPC_MODULE:validate_rsp(M, D1M0),
    D1M;
maybe_rsp_result(_D, D1M0) ->
    D1M0.

init() ->
    T = <<"init - client">>,
    L = [{{conn, #{event => init}},
          {send,
           #{type => req, method => configure, id => 0},
           #{phase => connected, reqs => #{0 => connected}}}
         }],
    [{T, test, E, R} || {E, R} <- L].

when_connected(timeout_0_retries) ->
    application:set_env(aestratum_client, connection_req_retries, 0),
    T = <<"when connected - timeout, 0 retries">>,
    L = [{{conn, #{event => timeout, id => 0, phase => connected}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(timeout_1_retries) ->
    application:set_env(aestratum_client, connection_req_retries, 1),
    T = <<"when connected - timeout, 1 retries">>,
    L = [{{conn, #{event => timeout, id => 0, phase => connected}},
          {send,
           #{type => req, method => configure},
           #{phase => connected, reqs => #{1 => connected}}}
         },
         {{conn, #{event => timeout, id => 1, phase => connected}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(jsonrpc_rsp_parse_error) ->
    T = <<"when connected - jsonrpc_rsp_parse_error">>,
    {E, R} = conn_make_parse_error(disconnected, #{}),
    prep_connected(T) ++ [{T, test, E, R}];
when_connected(jsonrpc_rsp_invalid_msg) ->
    T = <<"when connected - jsonrpc_rsp_invalid_msg">>,
    {E, R} = conn_make_invalid_msg(disconnected, #{}),
    prep_connected(T) ++ [{T, test, E, R}];
when_connected(jsonrpc_rsp_invalid_method) ->
    T = <<"when connected - jsonrpc_rsp_invalid_method">>,
    {E, R} = conn_make_invalid_method(disconnected, #{}),
    prep_connected(T) ++ [{T, test, E, R}];
when_connected(jsonrpc_rsp_invalid_param) ->
    T = <<"when connected - jsonrpc_rsp_invalid_param">>,
    {E, R} = conn_make_invalid_param(disconnected, #{}),
    prep_connected(T) ++ [{T, test, E, R}];
when_connected(subscribe_rsp) ->
    T = <<"when connected - subsribe_rsp">>,
    L = [{{conn, #{type => rsp, method => subscribe, id => 0,
                   result => [null, <<"00112233">>]}},
          {stop, #{phase => disconnected, reqs => #{}}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(authorize_rsp) ->
    T = <<"when connected - subsribe_rsp">>,
    L = [{{conn, #{type => rsp, method => authorize, id => 0, result => true}},
          {stop, #{phase => disconnected, reqs => #{}}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(set_target_ntf) ->
    T = <<"when connected - set_target_ntf">>,
    L = [{{conn, #{type => ntf, method => set_target, target => ?TEST_TARGET}},
          {no_send,
           #{phase => connected}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(notify_ntf) ->
    T = <<"when connected - notify_ntf">>,
    L = [{{conn, #{type => ntf, method => notify, job_id => ?TEST_JOB_ID,
                   block_version => 1, block_hash => ?TEST_BLOCK_HASH,
                   empty_queue => true}},
          {no_send,
           #{phase => connected}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(found_share_msg) ->
    T = <<"when connected - found_share_msg">>,
    MinerNonce = ?NONCE_MODULE:new(miner, 1, 4),
    L = [{{miner, #{event => found_share,
                    share => #{job_id => ?TEST_JOB_ID,
                               miner_nonce => MinerNonce,
                               pow => ?TEST_POW}}},
          {no_send,
           #{phase => connected}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L];
when_connected(configure_rsp) ->
    T = <<"when connected - configure_rsp">>,
    L = [{{conn, #{type => rsp, method => configure, id => 0, result => []}},
          {send,
           #{type => req, method => subscribe, id => 1},
           #{phase => configured, reqs => #{1 => configured},
             extra_nonce => undefined}}
         }],
    prep_connected(T) ++ [{T, test, E, R} || {E, R} <- L].

when_configured(timeout) ->
    T = <<"when configured - timeout">>,
    L = [{{conn, #{event => timeout, id => 1, phase => configured}},
          {send,
           #{type => req, method => subscribe, id => 2},
           #{phase => configured, reqs => #{2 => configured}}}
         },
         {{conn, #{event => timeout, id => 2, phase => configured}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(jsonrpc_rsp_parse_error) ->
    T = <<"when configured - jsonrpc_rsp_parse_error">>,
    {E, R} = conn_make_parse_error(disconnected, #{}),
    prep_configured(T) ++ [{T, test, E, R}];
when_configured(jsonrpc_rsp_invalid_msg) ->
    T = <<"when configured - jsonrpc_rsp_invalid_msg">>,
    {E, R} = conn_make_invalid_msg(disconnected, #{}),
    prep_configured(T) ++ [{T, test, E, R}];
when_configured(jsonrpc_rsp_invalid_method) ->
    T = <<"when configured - jsonrpc_rsp_invalid_method">>,
    {E, R} = conn_make_invalid_method(disconnected, #{}),
    prep_configured(T) ++ [{T, test, E, R}];
when_configured(jsonrpc_rsp_invalid_param) ->
    T = <<"when configured - jsonrpc_rsp_invalid_param">>,
    {E, R} = conn_make_invalid_param(disconnected, #{}),
    prep_configured(T) ++ [{T, test, E, R}];
when_configured(configure_rsp) ->
    T = <<"when configured - configure_rsp">>,
    L = [{{conn, #{type => rsp, method => configure, id => 1,
                   result => []}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(authorize_rsp) ->
    T = <<"when configured - authorize_rsp">>,
    L = [{{conn, #{type => rsp, method => authorize, id => 1, result => false}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(set_target_ntf) ->
    T = <<"when configured - set_target_ntf">>,
    L = [{{conn, #{type => ntf, method => set_target, target => ?TEST_TARGET}},
          {no_send,
           #{phase => configured}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(notify_ntf) ->
    T = <<"when configured - notify_ntf">>,
    L = [{{conn, #{type => ntf, method => notify, job_id => ?TEST_JOB_ID,
                   block_version => 1, block_hash => ?TEST_BLOCK_HASH,
                   empty_queue => true}},
          {no_send,
           #{phase => configured}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(found_share_msg) ->
    T = <<"when configured - found_share_msg">>,
    MinerNonce = ?NONCE_MODULE:new(miner, 1, 4),
    L = [{{miner, #{event => found_share,
                    share => #{job_id => ?TEST_JOB_ID,
                               miner_nonce => MinerNonce,
                               pow => ?TEST_POW}}},
          {no_send,
           #{phase => configured}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L];
when_configured(subscribe_rsp) ->
    T = <<"when configured - success_rsp">>,
    ExtraNonce = ?NONCE_MODULE:new(extra, 16#01020304, 4),
    L = [{{conn, #{type => rsp, method => subscribe, id => 1,
                   result => [null, ?NONCE_MODULE:to_hex(ExtraNonce)]}},
          {send,
           #{type => req, method => authorize, id => 2},
           #{phase => subscribed, reqs => #{2 => subscribed},
             extra_nonce => ExtraNonce}}
         }],
    prep_configured(T) ++ [{T, test, E, R} || {E, R} <- L].

when_subscribed(timeout) ->
    T = <<"when subscribed - timeout">>,
    L = [{{conn, #{event => timeout, id => 2, phase => subscribed}},
          {send,
           #{type => req, method => authorize, id => 3},
           #{phase => subscribed, reqs => #{3 => subscribed}}}
         },
         {{conn, #{event => timeout, id => 3, phase => subscribed}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(jsonrpc_rsp_parse_error) ->
    T = <<"when subscribed - jsonrpc_rsp_parse_error">>,
    {E, R} = conn_make_parse_error(disconnected, #{}),
    prep_subscribed(T) ++ [{T, test, E, R}];
when_subscribed(jsonrpc_rsp_invalid_msg) ->
    T = <<"when subscribed - jsonrpc_rsp_invalid_msg">>,
    {E, R} = conn_make_invalid_msg(disconnected, #{}),
    prep_subscribed(T) ++ [{T, test, E, R}];
when_subscribed(jsonrpc_rsp_invalid_method) ->
    T = <<"when subscribed - jsonrpc_rsp_invalid_method">>,
    {E, R} = conn_make_invalid_method(disconnected, #{}),
    prep_subscribed(T) ++ [{T, test, E, R}];
when_subscribed(jsonrpc_rsp_invalid_param) ->
    T = <<"when subscribed - jsonrpc_rsp_invalid_param">>,
    {E, R} = conn_make_invalid_param(disconnected, #{}),
    prep_subscribed(T) ++ [{T, test, E, R}];
when_subscribed(configure_rsp) ->
    T = <<"when subscribed - configure_rsp">>,
    L = [{{conn, #{type => rsp, method => configure, id => 2, result => []}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(subscribe_rsp) ->
    T = <<"when subscribed - subscribe_rsp">>,
    L = [{{conn, #{type => rsp, method => subscribe, id => 2,
                   result => [null, <<"0011">>]}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(authorize_failure_rsp) ->
    T = <<"when subscribed - authorize_failure_rsp">>,
    L = [{{conn, #{type => rsp, method => authorize, id => 2, result => false}},
          {stop,
           #{phase => disconnected, reqs => #{}}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(set_target_ntf) ->
    T = <<"when subscribed - set_target_ntf">>,
    L = [{{conn, #{type => ntf, method => set_target, target => ?TEST_TARGET}},
          {no_send,
           #{phase => subscribed}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(notify_ntf) ->
    T = <<"when subscribed - notify_ntf">>,
    L = [{{conn, #{type => ntf, method => notify, job_id => ?TEST_JOB_ID,
                   block_version => 1, block_hash => ?TEST_BLOCK_HASH,
                   empty_queue => true}},
          {no_send,
           #{phase => subscribed}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(found_share_msg) ->
    T = <<"when subscribed - found_share_msg">>,
    MinerNonce = ?NONCE_MODULE:new(miner, 16#11223344, 4),
    L = [{{miner, #{event => found_share,
                    share => #{job_id => ?TEST_JOB_ID,
                               miner_nonce => MinerNonce,
                               pow => ?TEST_POW}}},
          {no_send,
           #{phase => subscribed}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L];
when_subscribed(authorize_success_rsp) ->
    T = <<"when subscribed - authorize_success_rsp">>,
    L = [{{conn, #{type => rsp, method => authorize, id => 2, result => true}},
          {no_send,
           #{phase => authorized, reqs => #{}}}
         }],
    prep_subscribed(T) ++ [{T, test, E, R} || {E, R} <- L].

when_authorized(timeout) ->
    T = <<"when authorized - timeout">>,
    L = [{{conn, #{event => timeout, id => 10, phase => subscribed}},
        {no_send,
         #{phase => authorized, reqs => #{}}}
       }],
    prep_authorized(T) ++ [{T, test, E, R} || {E, R} <- L];
when_authorized(set_target_ntf) ->
    T = <<"when authorized - set_target_ntf">>,
    L = [{{conn, #{type => ntf, method => set_target, target => ?TEST_TARGET}},
          {no_send,
           #{phase => authorized, target => ?TEST_TARGET}}
         }],
    prep_authorized(T) ++ [{T, test, E, R} || {E, R} <- L];
when_authorized(notify_ntf) ->
    T = <<"when authorized - notify_ntf">>,
    meck:expect(?CLIENT_GENERATOR_MANAGER_MODULE, generate,
                fun(_, _) -> {ok, #{started => {1, 1}, queued => {0, 0}}} end),
    L = [{{conn, #{type => ntf, method => notify, job_id => ?TEST_JOB_ID,
                   block_version => 1, block_hash => ?TEST_BLOCK_HASH,
                   empty_queue => true}},
          {no_send,
           #{phase => authorized}}
         }],
    prep_authorized(T) ++ [{T, test, E, R} || {E, R} <- L];
when_authorized(found_share_msg) ->
    T = <<"when authorized - found_share_msg">>,
    MinerNonce = ?NONCE_MODULE:new(miner, 16#aabb, 2),
    L = [{{miner, #{event => found_share,
                    share => #{job_id => ?TEST_JOB_ID,
                               miner_nonce => MinerNonce,
                               pow => ?TEST_POW}}},
          {send,
           #{type => req, method => submit, id => 3, user => ?TEST_USER,
             job_id => ?TEST_JOB_ID,
             miner_nonce => ?NONCE_MODULE:to_hex(MinerNonce), pow => ?TEST_POW},
           #{phase => authorized, reqs => #{3 => authorized}}}
         }],
    prep_authorized(T) ++ [{T, test, E, R} || {E, R} <- L].

prep_connected(T) ->
    L = [conn_init()],
    [{T, no_test, E, R} || {E, R} <- L].

prep_configured(T) ->
    L = [conn_init(),
         conn_configure()],
    [{T, no_test, E, R} || {E, R} <- L].

prep_subscribed(T) ->
    L = [conn_init(),
         conn_configure(),
         conn_subscribe()],
    [{T, no_test, E, R} || {E, R} <- L].

prep_authorized(T) ->
    L = [conn_init(),
         conn_configure(),
         conn_subscribe(),
         conn_authorize()],
    [{T, no_test, E, R} || {E, R} <- L].

%% Configure request with Id 0 is sent.
%% Session state stays in connected phase, req with Id 0 has connected phase.
conn_init() ->
    {{conn, #{event => init}},
     {send,
      #{type => req, method => configure, id => 0},
      #{phase => connected, reqs => #{0 => connected}}}
    }.

%% Configure response with Id 0 received, subscribe request with Id 1 is sent.
%% Session state moves from connected to configured state,
conn_configure() ->
    {{conn, #{type => rsp, method => configure, id => 0, result => []}},
     {send,
      #{type => req, method => subscribe, id => 1},
      #{phase => configured, reqs => #{1 => configured}}}
    }.

conn_subscribe() ->
    {{conn, #{type => rsp, method => subscribe, id => 1,
              result => [null, <<"010101">>]}},
     {send,
      #{type => req, method => authorize, id => 2},
      #{phase => subscribed, reqs => #{2 => subscribed}}}
    }.

conn_authorize() ->
    {{conn, #{type => rsp, method => authorize, id => 2, result => true}},
     {no_send,
      #{phase => authorized, reqs => #{}}}
    }.

conn_make_parse_error(Phase, Reqs) ->
    {{conn, #{event => recv_data,
              data => <<"some random binary">>}},
     {stop,
      #{phase => Phase, reqs => Reqs}}
    }.

conn_make_invalid_msg(Phase, Reqs) ->
    {{conn, #{event => recv_data,
              data => <<"{\"jsonrpc\":\"2.0\",\"id\":\"none\"}">>}},
     {stop,
      #{phase => Phase, reqs => Reqs}}
    }.

conn_make_invalid_method(Phase, Reqs) ->
    {{conn, #{event => recv_data,
              data => <<"{\"jsonrpc\":\"2.0\",\"id\":200,\"method\":\"foo\",\"params\":[]}">>}},
     {stop,
      #{phase => Phase, reqs => Reqs}}
    }.

conn_make_invalid_param(Phase, Reqs) ->
    {{conn, #{event => recv_data,
              data => <<"{\"jsonrpc\":\"2.0\",\"id\":300,\"error\":[\"some invalid error\"}">>}},
     {stop,
      #{phase => Phase, reqs => Reqs}}
    }.

