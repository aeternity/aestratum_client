-module(aestratum_client_generator_manager).

-behaviour(gen_server).

%% API.
-export([start_link/0,
         stop/0,
         add/3,
         del/1,
         generate/2
        ]).

%% gen_server.
-export([init/1,
         handle_call/3,
         handle_cast/2
        ]).

-type id()            :: aestratum_client_miner:id().

-type repeats()       :: aestratum_miner:repeats().

-type extra_nonce()   :: aestratum_nonce:part_nonce().

-type worker_count()  :: non_neg_integer().

-type stats()         :: #{started => {worker_count(), repeats()},
                           queued  => {worker_count(), repeats()}}.

-record(state, {
          workers     :: orddict:orddict(id(), {pid(), repeats()})
         }).

-define(SERVER, ?MODULE).

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

-spec add(id(), pid(), repeats()) -> ok.
add(Id, Pid, Repeats) when
      is_integer(Id) and is_pid(Pid) and
      (is_integer(Repeats) and (Repeats > 0)) ->
    gen_server:call(?SERVER, {add, Id, Pid, Repeats}, infinity).

-spec del(id()) -> ok.
del(Id) when is_integer(Id) ->
    gen_server:call(?SERVER, {del, Id}, infinity).

%% TODO
-spec generate(term(), extra_nonce()) ->
    {ok, stats()} | {error, miner_nonce_exhausted}.
generate(Job, ExtraNonce) ->
    gen_server:call(?SERVER, {generate, Job, ExtraNonce}, infinity).

%% gen_server callbacks.

init([]) ->
    {ok, #state{workers = orddict:new()}}.

handle_call({add, Id, Pid, Repeats}, _From, #state{workers = Workers} = State) ->
    State1 = State#state{workers = orddict:store(Id, {Pid, Repeats}, Workers)},
    {reply, ok, State1};
handle_call({del, Id}, _From, #state{workers = Workers} = State) ->
    {reply, ok, State#state{workers = orddict:erase(Id, Workers)}};
handle_call({generate, Job, ExtraNonce}, _From, State) ->
    {ok, Reply, State1} = handle_generate(Job, ExtraNonce, State),
    {reply, Reply, State1}.

handle_cast(_Req, State) ->
    {noreply, State}.

%% Internal functions.

handle_generate(Job, ExtraNonce, #state{workers = Workers} = State) ->
    Workers1 = orddict:to_list(Workers),
    MinerNonceNBytes = aestratum_nonce:complement_nbytes(ExtraNonce),
    MaxMinerNonceVal = aestratum_nonce:max(MinerNonceNBytes),
    MaxRepeats = max_repeats(Workers1),
    %% For example, 16#ff is 255 which is the max miner nonce value. It ranges
    %% from 0 to 255, it covers 256 miner nonce value (repeats).
    case (MaxMinerNonceVal + 1) - MaxRepeats of
        N when N >= 0 ->
            %% N is a max number that can be used as an initial miner nonce
            %% value in order not to cause nonce overflow.
            MinerNonceVal = random_miner_nonce_value(N),
            MinerNonce = aestratum_nonce:new(miner, MinerNonceVal, MinerNonceNBytes),
            Stats = #{started => {0, 0}, queued => {0, 0}},
            %% Shuffle the worker list so the workers are assigned random
            %% miner nonces.
            Workers2 = shuffle(Workers1),
            Reply = generate(Workers2, Job, ExtraNonce, MinerNonce, Stats),
            {ok, {ok, Reply}, State};
        _Other ->
            %% The workers cover more repeats than there are miner nonces.
            %% The workers could still start mining, some could mine the same
            %% nonces. This is unlikely to happen though. Therefore, this case
            %% is not handled as it possibly should be, and just error is
            %% returned.
            %% TODO: ^ low priority.
            {ok, {error, miner_nonce_exhausted}, State}
    end.

%% This function is only called when the miner nonce values are not exhausted.
generate([{_Id, {Pid, Repeats}} | Workers], Job, ExtraNonce, MinerNonce, Stats) ->
    {Action, Repeats} = send_job(Pid, Job, ExtraNonce, MinerNonce),
    MinerNonceVal = aestratum_nonce:value(MinerNonce) + Repeats - 1,
    MinerNonce1 = aestratum_nonce:update(MinerNonceVal, MinerNonce),
    Stats1 = update_stats(Action, Repeats, Stats),
    generate(Workers, Job, ExtraNonce, MinerNonce1, Stats1);
generate([], _Job, _ExtraNonce, _MinerNonce, Stats) ->
    Stats.

max_repeats(Workers) ->
    lists:foldl(fun({_Id, {_Pid, Repeats}}, Count) ->
                        Count + Repeats
                end, 0, Workers).

send_job(Pid, Job, ExtraNonce, MinerNonce) ->
    aestratum_client_generator_worker:generate(Pid, Job, ExtraNonce, MinerNonce).

random_miner_nonce_value(Max) ->
    rand:uniform(Max + 1) - 1.

shuffle([]) ->
    [];
shuffle([_X] = L) ->
    L;
shuffle(L) ->
    [X || {_,X} <- lists:sort([{rand:uniform(), N} || N <- L])].

update_stats(started, Repeats, #{started := {WorkerCount, NonceCount}} = Stats) ->
    Stats#{started => {WorkerCount + 1, NonceCount + Repeats}};
update_stats(queued, Repeats, #{queued := {WorkerCount, NonceCount}} = Stats) ->
    Stats#{queued => {WorkerCount + 1, NonceCount + Repeats}}.
