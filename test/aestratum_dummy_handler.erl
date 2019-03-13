-module(aestratum_dummy_handler).

-behaviour(gen_server).

-export([start_link/2,
         handle_event/2,
         state_to_map/2,
         stop/1
        ]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2
        ]).

-record(state, {
          pid,
          module,
          session
         }).

start_link(Module, SessionOpts) ->
    gen_server:start_link(?MODULE, [Module, SessionOpts], []).

handle_event(Pid, Event) ->
    gen_server:call(Pid, Event).

state_to_map(Pid, Session) ->
    gen_server:call(Pid, {state_to_map, Session}).

stop(Pid) ->
    gen_server:cast(Pid, stop).

init([Module, SessionOpts]) ->
    {ok, #state{pid = self(), module = Module,
                session = Module:new(SessionOpts)}}.

handle_call({conn, _Event} = ConnEvent, _From,
            #state{module = Module, session = Session} = State) ->
	Res = Module:handle_event(ConnEvent, Session),
    {reply, result(Res, State), State#state{session = session(Res)}};
handle_call({miner, _Event} = MinerEvent, _From,
            #state{module = Module, session = Session} = State) ->
	Res = Module:handle_event(MinerEvent, Session),
    {reply, result(Res, State), State#state{session = session(Res)}};
handle_call({state_to_map, Session}, _From,
            #state{module = Module} = State) ->
    {reply, Module:state(Session), State}.

handle_cast(stop, #state{} = State) ->
    {stop, normal, State}.

handle_info(timeout, #state{} = State) ->
    %% NOTE: this shouldn't happen here. The timeouts are
    %% simulated by handle_event.
    {noreply, State};
handle_info(_Info, #state{} = State) ->
    {noreply, State}.

result({send, Data, Session} = Res, #state{module = Module} = State) ->
    case send_data(Data) of
        ok ->
            Res;
        {error, _Rsn} ->
            Res1 = Module:handle_event({conn, close}, Session),
            result(Res1, State)
    end;
result({no_send, _Session} = Res, _State) ->
    Res;
result({stop, _Session} = Res, _State) ->
    Res.

session({_Action, Session}) ->
    Session;
session({send, _Data, Session}) ->
    Session.

send_data(_Data) ->
    ok.
