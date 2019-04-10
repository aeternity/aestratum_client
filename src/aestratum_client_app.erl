-module(aestratum_client_app).

-behavior(application).

%% application callbacks.
-export([start/2,
         stop/1
        ]).

%% application callbacks.

start(_Type, _Args) ->
    {ok, Cfg} = aestratum_client_config:read(),
    aestratum_client_sup:start_link(Cfg).

stop(_State) ->
	ok.

