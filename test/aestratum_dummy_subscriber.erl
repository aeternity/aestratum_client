-module(aestratum_dummy_subscriber).

-behaviour(gen_server).

-export([start_link/1,
         stop/1,
         events/1
        ]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2
        ]).

-record(state, {
          pid,
          name,
          events
         }).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [Name], []).

stop(Name) ->
    gen_server:stop(Name).

events(Name) ->
    gen_server:call(Name, events).

init([Name]) ->
    {ok, #state{pid = self(), name = Name, events = []}}.

handle_call(events, _From, #state{events = Events} = State) ->
    {reply, {ok, Events}, State}.

handle_cast(_Req, State) ->
    {noreply, State}.

handle_info(Event, #state{events = Events} = State) ->
    {noreply, #state{events = [Event | Events]}}.

