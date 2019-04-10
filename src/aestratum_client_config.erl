-module(aestratum_client_config).

%% API.
-export([read/0]).

-export_type([config/0]).

-type config() :: map().

%% TODO: config will be read from a config file.
-spec read() -> {ok, config()}.
read() ->
    Cfg =
        #{conn_cfg =>
            #{transport    => tcp,
              socket_opts  => [],
              host         => <<"localhost">>, %%<<"pool.aeternity.com">>,
              port         => 9999,
              req_timeout  => 30000,
              req_retries  => 3},
          user_cfg =>
            #{user => <<"ak_DummyPubKeyDoNotEverUse999999999999999999999999999">>,
              %% worker       => TODO
              password     => null},
          miners_cfg =>
            [#{exec        => <<"mean29-generic">>,
               exec_group  => <<"aecuckoo">>,
               extra_args  => <<>>,
               hex_enc_hdr => false,
               repeats     => 10, %% TODO: auto
               edge_bits   => 29,
               instances   => undefined},
             #{exec        => <<"mean29-generic">>,
               exec_group  => <<"aecuckoo">>,
               extra_args  => <<>>,
               hex_enc_hdr => false,
               repeats     => 20, %% TODO: auto
               edge_bits   => 29,
               instances   => undefined}]},
    {ok, Cfg}.

