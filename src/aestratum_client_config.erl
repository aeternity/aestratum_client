-module(aestratum_client_config).

%% API.
-export([get/0]).

-export_type([config/0]).

-type config() :: map().

%% TODO: config will be read from a config file.
get() ->
    #{conn =>
        #{transport    => tcp,
          socket_opts  => [],
          host         => <<"localhost">>, %%<<"pool.aeternity.com">>,
          port         => 9999,
          req_timeout  => 30000,
          req_retries  => 3},
      user => %% TODO: user => user is weird, change to user_cfg => user
        #{user => <<"ak_DummyPubKeyDoNotEverUse999999999999999999999999999">>,
          %% worker       => TODO
          password     => null},
      miners =>
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
           instances   => undefined}]}.

