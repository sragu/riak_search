%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(riak_search_utils).

-export([
    combine_terms/2,
    to_atom/1,
    to_binary/1,
    to_utf8/1,
    to_boolean/1,
    to_list/1,
    to_integer/1,
    to_float/1,
    from_binary/1,
    current_key_clock/0,
    choose/1,
    coalesce/1, coalesce/2,
    binary_inc/2,
    ets_keys/1,
    consult/1,
    ptransform/2
]).

-include("riak_search.hrl").
-ifdef(TEST).
-ifdef(EQC).
-include_lib("eqc/include/eqc.hrl").
-endif.
-include_lib("eunit/include/eunit.hrl").
-endif.

%% Given to terms, combine the properties in some sort of reasonable
%% way. This basically means concatenating the score and the word list
%% values, and then unioning the rest of the props.
combine_terms({Index, DocID, Props1}, {Index, DocID, Props2}) ->
    %% score list is concatenation of each term's scores
    ScoreList1 = proplists:get_value(score, Props1, []),
    ScoreList2 = proplists:get_value(score, Props2, []),
    ScoreList = ScoreList1++ScoreList2,

    %% word position is concatentation of each term's scores
    WordPos1 = proplists:get_value(p, Props1, []),
    WordPos2 = proplists:get_value(p, Props2, []),
    WordPos = WordPos1++WordPos2,

    %% only include the common properties from the rest of the list
    Intersection = sets:to_list(sets:intersection(sets:from_list(Props1),
                                                  sets:from_list(Props2))),

    %% overwrite whatever score/position/frequency came out of intersection
    NewProps = lists:foldl(fun({K, V}, Acc) ->
                                   lists:keystore(K, 1, Acc, {K, V})
                           end,
                           Intersection,
                           [{score, ScoreList},
                            {p, WordPos}]
                           ),
    {Index, DocID, NewProps};
combine_terms(Other1, Other2) ->
    error_logger:error_msg("Could not combine terms: [~p, ~p]~n", [Other1, Other2]),
    throw({could_not_combine, Other1, Other2}).

to_list(A) when is_atom(A) -> atom_to_list(A);
to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(I) when is_integer(I) -> integer_to_list(I);
to_list(F) when is_float(F) -> float_to_list(F);
to_list(L) when is_list(L) -> L.

to_atom(A) when is_atom(A) -> A;
to_atom(B) when is_binary(B) -> to_atom(binary_to_list(B));
to_atom(I) when is_integer(I) -> to_atom(integer_to_list(I));
to_atom(L) when is_list(L) -> list_to_atom(binary_to_list(list_to_binary(L))).

to_binary(A) when is_atom(A) -> to_binary(atom_to_list(A));
to_binary(B) when is_binary(B) -> B;
to_binary(I) when is_integer(I) -> to_binary(integer_to_list(I));
to_binary(L) when is_list(L) -> list_to_binary(L).

to_utf8(A) when is_atom(A) -> atom_to_binary(A, utf8);
to_utf8(B) when is_binary(B) -> B;
to_utf8(I) when is_integer(I) -> to_utf8(integer_to_list(I));
to_utf8(F) when is_float(F) -> to_utf8(mochinum:digits(F));
to_utf8(L) when is_list(L) -> unicode:characters_to_binary(L).


to_integer(A) when is_atom(A) -> to_integer(atom_to_list(A));
to_integer(B) when is_binary(B) -> to_integer(binary_to_list(B));
to_integer(I) when is_integer(I) -> I;
to_integer(L) when is_list(L) -> list_to_integer(L).

to_float(F) ->
    list_to_float(to_list(F)).

to_boolean(B) ->
    A = to_atom(B),
    (A == yes) orelse (A == true) orelse (A == '1').

from_binary(B) when is_binary(B) ->
    binary_to_list(B);
from_binary(L) ->
    L.

%% Return a key clock to use for revisioning IFTVPs
current_key_clock() ->
    {MegaSeconds,Seconds,MilliSeconds}=erlang:now(),
    (MegaSeconds * 1000000000000) + 
    (Seconds * 1000000) + 
    MilliSeconds.

%% Choose a random element from the List or Array.
choose(List) when is_list(List) ->
    random:seed(now()),
    N = random:uniform(length(List)),
    lists:nth(N, List);
choose(Array) when element(1, Array) == array ->
    random:seed(now()),
    N = random:uniform(Array:size()),
    Array:get(N - 1).

%% Take the first defined element.
coalesce(undefined, B) -> B;
coalesce(A, _) -> A.

coalesce([undefined|T]) -> 
    coalesce(T);
coalesce([H|_]) ->
    H;
coalesce([]) ->
    undefined.

%% Given an integer or binary Term, increment it by Amt. Used for
%% making inclusive or exclusive ranges.
binary_inc(Term, Amt) when is_list(Term) ->
    NewTerm = binary_inc(list_to_binary(Term), Amt),
    binary_to_list(NewTerm);
binary_inc(Term, Amt) when is_binary(Term) ->
    Bits = size(Term) * 8,
    <<Int:Bits/integer>> = Term,
    NewInt = binary_inc(Int, Amt),
    <<NewInt:Bits/integer>>;
binary_inc(Term, Amt) when is_integer(Term) ->
    Term + Amt;
binary_inc(Term, _) ->
    throw({unhandled_type, binary_inc, Term}).

%% Given an ETS table, return a list of keys.
ets_keys(Table) ->
    Key = ets:first(Table),
    ets_keys_1(Table, Key).
ets_keys_1(_Table, '$end_of_table') ->
    [];
ets_keys_1(Table, Key) ->
    [Key|ets_keys_1(Table, ets:next(Table, Key))].

%% Given a binary, return an Erlang term.
consult(Binary) ->
    case erl_scan:string(riak_search_utils:to_list(Binary)) of
        {ok, Tokens, _} -> 
            consult_1(Tokens);
        Error ->
            Error
    end.
consult_1(Tokens) ->
    case erl_parse:parse_exprs(Tokens) of
        {ok, AST} ->
            consult_2(AST);
        Error ->
            Error
    end.
consult_2(AST) ->
    case erl_eval:exprs(AST, []) of
        {value, Term, _} ->
            {ok, Term};
        Error ->
            Error
    end.


%% Run a transform operation in parallel. Results are returned as a
%% list, ordering is not guaranteed in any way. This was implemented
%% as a simple substitute to the plists.erl module. The plists module
%% has some subtle bugs because messages are not tagged with
%% Refs. This causes heisenbugs.
ptransform(F, List) ->
    Schedulers = erlang:system_info(schedulers),
    ptransform(F, List, Schedulers).

%% Run a map operation in parallel.
ptransform(F, List, NumProcesses) ->
    %% Calculate our batch size by dividing the size of the list by
    %% the number of processes. Batch size should be at least 1.
    ListLength = length(List),
    BatchSize = lists:max([1, ListLength div NumProcesses]),
    
    %% Create a ref, used to prevent later interference.
    Ref = make_ref(),
    Pids = ptransform_spawn(F, List, ListLength, Ref, BatchSize, []),
    ptransform_collect(Ref, Pids, []).

ptransform_spawn(F, List, ListLength, Ref, BatchSize, Pids) when List /= [] ->
    %% Get the next BatchSize items from list, spawn a map that sends
    %% results back to the collector.
    case ListLength < BatchSize of
        true ->
            {Pre, Post} = {List, []},
            NewListLength = 0;
        false -> 
            {Pre, Post} = lists:split(BatchSize, List),
            NewListLength = ListLength - BatchSize
    end,

    %% Spawn up a worker for this chunk.
    Parent = self(),
    SpawnF = fun() ->
                     Results = lists:map(F, Pre),
                     Parent ! {results, Results, self(), Ref}
             end,
    Pid = erlang:spawn_link(SpawnF),
    ptransform_spawn(F, Post, NewListLength, Ref, BatchSize, [Pid|Pids]);
ptransform_spawn(_, [], 0, _, _, Pids) ->
    %% No more items left in list, return Pids.
    Pids.

ptransform_collect(Ref, Pids, Acc) when Pids /= [] ->
    %% Collect a chunk, and concat results.
    receive 
        {results, Results, Pid, Ref} ->
            NewPids = Pids -- [Pid],
            NewAcc = Results ++ Acc,
            ptransform_collect(Ref, NewPids, NewAcc)
    end;
ptransform_collect(_, [], Acc) ->
    %% We've read from all the pids, so return.
    Acc.

-ifdef(TEST).

ptransform_test() ->
    Test = fun(List) ->
                   F = fun(X) -> X * 2 end,
                   ?assertEqual(lists:sort(ptransform(F, List)), lists:map(F, List))
           end,
    Test(lists:seq(0, 0)),
    Test(lists:seq(1, 1)),
    Test(lists:seq(1, 2)),
    Test(lists:seq(1, 3)),
    Test(lists:seq(1, 20)),
    Test(lists:seq(1, 57)).

-ifdef(EQC).

-define(QC_OUT(P),
        eqc:on_output(fun(Str, Args) -> io:format(user, Str, Args) end, P)).

ptransform_test_qc_test() ->
    F = fun(X) -> X * 2 end,
    Prop = ?FORALL({List, NumProcesses}, {list(int()), choose(1, 8)},
                   lists:sort(ptransform(F, List, NumProcesses)) ==
                   lists:sort(lists:map(F, List))),
    ?assert(eqc:quickcheck(eqc:numtests(500, ?QC_OUT(Prop)))).

-endif. % EQC
-endif. % TEST
