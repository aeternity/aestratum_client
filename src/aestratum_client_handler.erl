-module(aestratum_client_handler).

-behaviour(gen_server).

%% TODO: eunit

%% API
-export([start_link/1,
         status/0,
         stop/0
        ]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2
        ]).

-include("aestratum_client_log.hrl").

-type config()      :: aestratum_client_config:config().

-type socket()      :: gen_tcp:socket().

-type transport()   :: gen_tcp
                     | ssl.

-type session()     :: aestratum_client_session:session()
                     | undefined.

-record(state, {
          socket    :: socket(),
          transport :: transport(),
          session   :: session()
         }).

-define(SERVER, ?MODULE).

-define(IS_MSG(T), ((T =:= tcp) or (T =:= ssl))).
-define(IS_CLOSE(C), ((C =:= tcp_closed) or (C =:= ssl_closed))).
-define(IS_ERROR(E), ((E =:= tcp_error) or (E =:= ssl_error))).

%% API.

-spec start_link(config()) -> {ok, pid()}.
start_link(Cfg) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Cfg, []).

-spec status() -> map().
status() ->
    gen_server:call(?SERVER, status).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

%% gen_server callbacks.

init(#{conn_cfg := ConnCfg, user_cfg := UserCfg}) ->
    Transport = transport(maps:get(transport, ConnCfg)),
    Host = maps:get(host, ConnCfg),
    Port = maps:get(port, ConnCfg),
    SocketOpts = maps:get(socket_opts, ConnCfg),
    {ok, Socket} = connect(Transport, Host, Port, SocketOpts),
    ?INFO("socket_connected, transport: ~p, host: ~p, port: ~p",
          [Transport, Host, Port]),
    set_socket_opts(Socket, [binary, {active, once}, {packet, line}, {keepalive, true}]),
    SessionOpts = UserCfg#{host => Host, port => Port},
    gen_server:cast(self(), {init_session, SessionOpts}),
    {ok, #state{socket = Socket, transport = Transport}}.

handle_call(status, _From, State) ->
    Reply = handle_status(State),
    {reply, Reply, State}.

handle_cast({init_session, SessionOpts}, #state{socket = Socket} = State) when
      Socket =/= undefined ->
    Session = aestratum_client_session:new(SessionOpts),
    Event = #{event => init},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State);
handle_cast({init_session, _SessionOpts}, State) ->
    {noreply, State}.

handle_info({SocketType, _Socket, Data}, State) when ?IS_MSG(SocketType) ->
    handle_socket_data(Data, State);
handle_info({SocketClose, _Socket}, State) when ?IS_CLOSE(SocketClose) ->
    handle_socket_close(State);
handle_info({SocketError, _Socket, Rsn}, State) when ?IS_ERROR(SocketError) ->
    handle_socket_error(Rsn, State);
handle_info({conn, _Event} = ConnEvent, State) ->
    handle_conn_event(ConnEvent, State);
handle_info({miner, _Event} = MinerEvent, State) ->
    handle_miner_event(MinerEvent, State).

terminate(_Rsn, #state{session = Session}) when Session =/= undefined ->
    aestratum_client_session:close(Session);
terminate(_Rsn, _State) ->
    ok.

%% Internal functions.

handle_socket_data(Data, #state{socket = Socket, session = Session} = State) ->
    Event = #{event => recv_data, data => Data},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    case is_stop(Res) of
        true  -> ok;
        false -> inet:setopts(Socket, [{active, once}])
    end,
    result(Res, State).

handle_socket_close(#state{session = Session} = State) ->
    ?WARN("socket_close", []),
    Event = #{event => close},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_socket_error(Rsn, #state{session = Session} = State) ->
    ?WARN("socket_error, reason: ~p", [Rsn]),
    Event = #{event => close},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_conn_event({conn, Event}, #state{session = Session} = State) ->
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_miner_event({miner, Event}, #state{session = Session} = State) ->
    Res = aestratum_client_session:handle_event({miner, Event}, Session),
    result(Res, State).

handle_status(#state{socket = Socket, transport = Transport,
                     session = Session}) ->
    #{conn => #{socket => Socket, transport => Transport},
      session => aestratum_client_session:status(Session)}.

result({send, Data, Session},
       #state{socket = Socket, transport = Transport} = State) ->
    case send_data(Data, Socket, Transport) of
        ok ->
            {noreply, State#state{session = Session}};
        {error, Rsn} ->
            ?WARN("socket_send, reason: ~p, data: ~p", [Rsn, Data]),
            Event = #{event => close},
            Res = aestratum_client_session:handle_event({conn, Event}, Session),
            result(Res, State)
    end;
result({no_send, Session}, State) ->
    {noreply, State#state{session = Session}};
result({stop, Session}, State) ->
    {stop, normal, State#state{session = Session}}.

send_data(Data, Socket, Transport) ->
    Transport:send(Socket, Data).

is_stop({stop, _Session}) -> true;
is_stop(_Other) -> false.

transport(tcp) -> gen_tcp;
transport(ssl) -> ssl.

connect(Transport, Host, Port, Opts) ->
    Transport:connect(binary_to_list(Host), Port, Opts).

set_socket_opts(Socket, Opts) when Socket =/= undefined ->
    inet:setopts(Socket, Opts);
set_socket_opts(_Socket, _Opts) ->
    ok.

