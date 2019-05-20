-module(aestratum_client).

-export([status/0,
         stop/0
        ]).

-spec status() -> map().
status() ->
    aestratum_client_handler:status().

-spec stop() -> ok.
stop() ->
    aestratum_client_handler:stop().

