-module(aestratum_client_app).

-behavior(application).

-export([start/2,
         stop/1
        ]).

start(_Type, _Args) ->
    aestratum_client_sup:start_link(#{}).

stop(_State) ->
	ok.

transport(tcp) -> gen_tcp;
transport(ssl) -> ssl.

