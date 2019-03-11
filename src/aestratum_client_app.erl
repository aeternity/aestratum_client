-module(aestratum_client_app).

-behavior(application).

%% application callbacks.
-export([start/2,
         stop/1
        ]).

%% application callbacks.

start(_Type, _Args) ->
    Config = aestratum_client_config:get(),
    aestratum_client_sup:start_link(Config).

stop(_State) ->
	ok.

