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

-record(state, {
          socket,
          transport,
          module,
          session
         }).

-define(SERVER, ?MODULE).

-define(DEFAULT_TRANSPORT, tcp).
-define(DEFAULT_SOCKET_OPTS, []).

-define(IS_MSG(T), ((T =:= tcp) or (T =:= ssl))).
-define(IS_CLOSE(C), ((C =:= tcp_closed) or (C =:= ssl_closed))).
-define(IS_ERROR(E), ((E =:= tcp_error) or (E =:= ssl_error))).

%% API.

start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% gen_server callbacks.

init([Opts]) ->
    Transport = maps:get(transport, Opts, ?DEFAULT_TRANSPORT),
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    SocketOpts = maps:get(socket_opts, Opts, ?DEFAULT_SOCKET_OPTS),
    {ok, Socket} = Transport:connect(Host, Port, SocketOpts),
    ok = Transport:setopts(Socket, [{active, once}, {packet, line},
                                    {keepalive, true}] ++ SocketOpts),
    Mod = maps:get(module, Opts),
    gen_server:cast(self(), init_session),
    {ok, #state{socket = Socket, transport = Transport, module = Mod}}.


handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast(init_session, #state{module = Mod} = State) ->
    %% TODO: subscribe to miner events
    Session = Mod:new(),
    Res = Mod:handle_event({conn, init}, Session),
    result(Res, State).

handle_info({SocketType, _Socket, Data}, State) when ?IS_MSG(SocketType) ->
    handle_socket_data(Data, State);
handle_info({SocketClose, _Socket}, State) when ?IS_CLOSE(SocketClose) ->
	handle_socket_close(State);
handle_info({SocketError, _Socket, Rsn}, State) when ?IS_ERROR(SocketError) ->
    handle_socket_error(Rsn, State);
handle_info(timeout, State) ->
    handle_socket_timeout(State);
%% TODO
handle_info({miner, Event}, State) ->
    handle_miner_event(Event, State);
handle_info(_Info, State) ->
	{stop, normal, State}.

terminate(_Reason, #state{module = Mod, session = Session}) ->
    Mod:close(Session).

%% Internal functions.

handle_socket_data(Data, #state{socket = Socket, transport = Transport,
                                module = Mod, session = Session} = State) ->
	Res = Mod:handle_event({conn, Data}, Session),
	case is_stop(Res) of
	    true -> ok;
	    false -> Transport:setopts(Socket, [{active, once}])
    end,
    result(Res, State).

handle_socket_close(#state{module = Mod, session = Session} = State) ->
    Res = Mod:handle_event({conn, close}, Session),
    result(Res, State).

handle_socket_error(_Rsn, #state{module = Mod, session = Session} = State) ->
    %% TODO: log error
    Res = Mod:handle_event({conn, close}, Session),
    result(Res, State).

handle_socket_timeout(#state{module = Mod, session = Session} = State) ->
    Res = Mod:handle_event({conn, timeout}, Session),
    result(Res, State).

handle_miner_event(Event, #state{module = Mod, session = Session} = State) ->
    Res = Mod:handle_event({chain, Event}, Session),
    result(Res, State).

result({send, Data, #state{module = Mod} = Session},
       #state{socket = Socket, transport = Transport} = State) ->
    case send_data(Data, Socket, Transport) of
        ok ->
            {noreply, State#state{session = Session}};
        {error, _Rsn} ->
            Res = Mod:handle_event({conn, close}, Session),
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

