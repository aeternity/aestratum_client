-module(aestratum_client_handler).

-behaviour(gen_server).

%% TODO: eunit
%% TODO: type spec

%% API
-export([start_link/1]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2
        ]).

-type config() :: aestratum_client_config:config().

-record(state, {
          socket,
          transport,
          session
         }).

-define(SERVER, ?MODULE).

-define(IS_MSG(T), ((T =:= tcp) or (T =:= ssl))).
-define(IS_CLOSE(C), ((C =:= tcp_closed) or (C =:= ssl_closed))).
-define(IS_ERROR(E), ((E =:= tcp_error) or (E =:= ssl_error))).

%% API.

-spec start_link(config()) -> {ok, pid()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% gen_server callbacks.

init(#{conn := ConnConfig, user := UserConfig}) ->
    Transport = transport(maps:get(transport, ConnConfig)),
    Host = maps:get(host, ConnConfig),
    Port = maps:get(port, ConnConfig),
    SocketOpts = maps:get(socket_opts, ConnConfig),
    Socket = connect(Transport, Host, Port, SocketOpts),
    set_socket_opts(Socket, [{active, once}, {packet, line}, {keepalive, true}]),
    SessionOpts = UserConfig#{host => Host, port => Port},
    gen_server:cast(self(), {init_session, SessionOpts}),
    {ok, #state{socket = Socket, transport = Transport}}.

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

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
handle_info({conn, Event}, State) ->
    handle_conn_event(Event, State);
%% TODO
handle_info({miner, Event}, State) ->
    handle_miner_event(Event, State);
handle_info(_Info, State) ->
	{stop, normal, State}.

terminate(_Rsn, #state{session = Session}) when Session =/= undefined ->
    aestratum_client_session:close(Session);
terminate(_Rsn, _State) ->
    ok.

%% Internal functions.

handle_socket_data(Data, #state{socket = Socket, transport = Transport,
                                session = Session} = State) ->
    Event = #{event => recv_data, data => Data},
	Res = aestratum_client_session:handle_event({conn, Event}, Session),
	case is_stop(Res) of
	    true  -> ok;
	    false -> Transport:setopts(Socket, [{active, once}])
    end,
    result(Res, State).

handle_socket_close(#state{session = Session} = State) ->
    Event = #{event => close},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_socket_error(_Rsn, #state{session = Session} = State) ->
    %% TODO: log error
    Event = #{event => close},
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_conn_event({conn, Event}, #state{session = Session} = State) ->
    Res = aestratum_client_session:handle_event({conn, Event}, Session),
    result(Res, State).

handle_miner_event({miner, Event}, #state{session = Session} = State) ->
    Res = aestratum_client_session:handle_event({miner, Event}, Session),
    result(Res, State).

result({send, Data, Session},
       #state{socket = Socket, transport = Transport} = State) ->
    case send_data(Data, Socket, Transport) of
        ok ->
            {noreply, State#state{session = Session}};
        {error, _Rsn} ->
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
    case Transport:connect(binary_to_list(Host), Port, Opts) of
        {ok, Socket} -> Socket;
        _Other       -> undefined
    end.

set_socket_opts(Socket, Opts) when Socket =/= undefined ->
    inet:setops(Socket, Opts);
set_socket_opts(_Socket, _Opts) ->
    ok.

