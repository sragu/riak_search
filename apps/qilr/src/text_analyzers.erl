%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(text_analyzers).
-export([default_analyzer_factory/2]).

%% Mimics the DefaultAnalyzerFactory.
default_analyzer_factory(Text, [MinLength]) ->
    {ok, default(Text, MinLength)};
default_analyzer_factory(Text, _Other) ->
    default_analyzer_factory(Text, [3]).

default(Text, MinLength) ->
    [ begin
          U = unicode:characters_to_binary(
                ustring:tolower(W), ustring:encoding(), utf8),
          case is_stopword(U) of
              true -> skip;
              false -> U
          end
      end
      || W <- ubrk:words(ustring:new(Text, utf8), [skip_breaks]),
         %% mimic org.apache.lucene.analysis.LengthFilter,
         %% which does not incement position index
         MinLength =< ustring:length(W, graphemes)].

is_stopword(Term) when size(Term) == 2 -> 
    ordsets:is_element(Term, [<<"an">>, <<"as">>, <<"at">>, <<"be">>, <<"by">>, <<"if">>, <<"in">>, <<"is">>, <<"it">>, <<"no">>, <<"of">>, <<"on">>, <<"or">>, <<"to">>]);
is_stopword(Term) when size(Term) == 3 -> 
    ordsets:is_element(Term, [<<"and">>, <<"are">>, <<"but">>, <<"for">>, <<"not">>, <<"the">>, <<"was">>]);
is_stopword(Term) when size(Term) == 4 -> 
    ordsets:is_element(Term, [<<"into">>, <<"such">>, <<"that">>, <<"then">>, <<"they">>, <<"this">>, <<"will">>]);
is_stopword(Term) when size(Term) == 5 -> 
    ordsets:is_element(Term, [<<"their">>, <<"there">>, <<"these">>]);
is_stopword(_Term) -> 
    false.
