-module(aestratum_client_config).

%% API.
-export([read/0,
         user_map/1
        ]).

-export_type([config/0]).

-type mode()   :: silent
                | report.

-type config() :: map().

-spec read() -> {ok, config()}.
read() ->
    #{<<"connection">> := ConnCfg,
      <<"miners">> := MinersCfg,
      <<"user">> := UserCfg} = user_map(report),
    {ok,
     #{conn_cfg =>
           #{transport    => binary_to_atom(maps:get(<<"transport">>, ConnCfg, <<"tcp">>), utf8),
             host         => maps:get(<<"host">>, ConnCfg, <<"localhost">>),
             port         => maps:get(<<"port">>, ConnCfg),
             req_timeout  => maps:get(<<"req_timeout">>, ConnCfg) * 1000,
             req_retries  => maps:get(<<"req_retries">>, ConnCfg),
             socket_opts  => []}, %% not taken from config
       user_cfg =>
           #{account      => maps:get(<<"account">>, UserCfg),
             worker       => maps:get(<<"worker">>, UserCfg),
             password     => null}, %% not taken from config
       miners_cfg =>
           [maps:fold(
              fun (K, V, Acc) -> Acc#{binary_to_atom(K, utf8) => V} end,
              #{instances => undefined}, %% not taken from config
              MinerCfg) || MinerCfg <- MinersCfg]}}.

-spec user_map(mode()) -> map().
user_map(Mode) ->
    case application:get_env(aestratum_client, '$user_map') of
        undefined ->
            ok = read_config(Mode),
            user_map(Mode);
        {ok, Map} ->
            Map
    end.

config_file() ->
    case os:getenv("AESTRATUM_CLIENT_CONFIG") of
        false ->
            case application:get_env(aestratum_client, config) of
                {ok, F} ->
                    F;
                _ ->
                    search_default_config()
            end;
        F ->
            F
    end.

search_default_config() ->
    {ok, CWD} = file:get_cwd(),
    Dirs = [CWD, os:getenv("HOME")],
    search_config(Dirs, "aestratum_client.{json,yaml}").

search_config(Dirs, FileWildcard) ->
    lists:foldl(
      fun(D, undefined) ->
              error_logger:info_msg("Searching for config file ~s "
                                    "in directory ~s~n", [FileWildcard, D]),
              case filelib:wildcard(FileWildcard, D) of
                  [] -> undefined;
                  [F|_] -> filename:join(D, F)
              end;
         (_, Acc) -> Acc
      end, undefined, Dirs).

read_config(Mode) when Mode =:= silent; Mode =:= report ->
    case config_file() of
        undefined ->
            info_msg(
              Mode,
              "No config file specified; using default settings~n", []),
            ok;
        F ->
            info_msg(Mode, "Reading config file ~s~n", [F]),
            do_read_config(F, schema_filename(), store, Mode)
    end.

do_read_config(F, Schema, Action, Mode) ->
    case {filename:extension(F), Action} of
        {".json", store} -> store(read_json(F, Schema, Mode));
        {".yaml", store} -> store(read_yaml(F, Schema, Mode))
    end.

store([Vars0]) ->
    Vars = to_tree(Vars0),
    set_env(aestratum_client, '$user_config', Vars),
    set_env(aestratum_client, '$user_map', Vars0).


read_json(F, Schema, Mode) ->
    validate(
      try_decode(F, fun(F1) ->
                            jsx:consult(F1, [return_maps])
                    end, "JSON", Mode), F, Schema, Mode).

read_yaml(F, Schema, Mode) ->
    validate(
      try_decode(
        F,
        fun(F1) ->
                yamerl:decode_file(F1, [{str_node_as_binary, true},
                                        {map_node_format, map}])
        end, "YAML", Mode),
      F, Schema, Mode).

try_decode(F, DecF, Fmt, Mode) ->
    try DecF(F)
    catch
        error:E ->
            error_msg(Mode, "Error reading ~s file: ~s~n", [Fmt, F]),
            erlang:error(E)
    end.

validate(JSON, F, Schema, Mode) when is_list(JSON) ->
    check_validation([validate_(Schema, J) || J <- JSON], JSON, F, Mode).

vinfo(silent, _, _) ->
    ok;
vinfo(_, Res, F) ->
    error_logger:info_report([{validation, F}, {result, Res}]).

info_msg(silent, _, _) -> ok;
info_msg(report, Fmt, Args) ->
    error_logger:info_msg(Fmt, Args).

error_msg(silent, _, _) -> ok;
error_msg(report, Fmt, Args) ->
    error_logger:error_msg(Fmt, Args).

check_validation(Res, _JSON, F, Mode) ->
    vinfo(Mode, Res, F),
    case lists:foldr(
           fun({ok, M}, {Ok,Err}) when is_map(M) ->
                   {[M|Ok], Err};
              (Other, {Ok,Err}) ->
                   {Ok, [Other|Err]}
           end, {[], []}, Res) of
        {Ok, []} ->
            Ok;
        {_, Errors} ->
            erlang:error({validation_failed, Errors})
    end.

validate_(Schema, JSON) ->
    case filelib:is_regular(Schema) of
        true ->
            jesse:validate_with_schema(load_schema(Schema), JSON, []);
        false ->
            {error, {schema_file_not_found, Schema}}
    end.

schema_filename() ->
    filename:join(code:priv_dir(aestratum_client), "config_schema.json").

load_schema(F) ->
    [Schema] = jsx:consult(F, [return_maps]),
    application:set_env(aestratum_client, '$schema', Schema),
    Schema.

to_tree(Vars) ->
    to_tree_(expand_maps(Vars)).

expand_maps(M) when is_map(M) ->
    [{K, expand_maps(V)} || {K, V} <- maps:to_list(M)];
expand_maps(L) when is_list(L) ->
    [expand_maps(E) || E <- L];
expand_maps(E) ->
    E.

to_tree_(L) when is_list(L) ->
    lists:flatten([to_tree_(E) || E <- L]);
to_tree_({K, V}) ->
    {K, to_tree_(V)};
to_tree_(E) ->
    E.

set_env(App, K, V) ->
    error_logger:info_msg("Set config (~p): ~p = ~p~n", [App, K, V]),
    application:set_env(App, K, V).

