-module(eredis_sub).
-include("eredis.hrl").
-export([connect/0, connect/1, close/1]).
-export([subscribe/2, psubscribe/2]).
-export([recv/1]).
-export([unsubscribe/2, punsubscribe/2]).

-define(DEFAULT_HOST, "127.0.0.1").
-define(DEFAULT_PORT, 6379).
-define(DEFAULT_ACTIVE, false).
-define(DEFAULT_PASSWORD, <<>>).

%% TODO: encapsulate rest in eredis_parser (as it leaks it's abstraction).
-record(?MODULE, {socket, parser, rest = <<>>}).


connect() ->
    connect([]).

connect(Opts) ->
    Host = proplists:get_value(host, Opts, ?DEFAULT_HOST),
    Port = proplists:get_value(port, Opts, ?DEFAULT_PORT),
    Active = proplists:get_value(active, Opts, ?DEFAULT_ACTIVE),
    Password  = proplists:get_value(password, Opts, ?DEFAULT_PASSWORD),

    case gen_tcp:connect(Host, Port, [binary, {active, Active}, {reuseaddr, true}]) of
	{ok, Socket} ->
	    case authenticate(Socket, Password) of
		ok ->
		    NewState = #?MODULE{socket = Socket, parser = eredis_parser:init()},
		    {ok, NewState};
		{error, Reason} ->
		    {error, Reason}
	    end;
	{error, Reason} ->
	    {error, Reason}
    end.

close(S0) ->
    ok = gen_tcp:close(S0#?MODULE.socket).

subscribe(S0, Channels) ->
    Command = eredis:create_multibulk([<<"SUBSCRIBE">> | Channels]),    
    ok = gen_tcp:send(S0#?MODULE.socket, Command).

psubscribe(S0, Channels) ->
    Command = eredis:create_multibulk([<<"PSUBSCRIBE">> | Channels]),
    ok = gen_tcp:send(S0#?MODULE.socket, Command).

unsubscribe(S0, Channels) ->
    Command = eredis:create_multibulk([<<"UNSUBSCRIBE">> | Channels]),
    ok = gen_tcp:send(S0#?MODULE.socket, Command).

punsubscribe(S0, Channels) ->
    Command = eredis:create_multibulk([<<"PUNSUBSCRIBE">> | Channels]),
    ok = gen_tcp:send(S0#?MODULE.socket, Command).

recv(S0) ->
    fetch_response(S0).


authenticate(_Socket, <<>>) ->
    ok;

authenticate(Socket, Password) ->
    case gen_tcp:send(Socket, [<<"AUTH">>, <<" ">>, Password, <<"\r\n">>]) of
        ok ->
	    {ok, _, _} = do_fetch_response(Socket, eredis_parser:init(), <<>>);
        {error, Reason} ->
            {error, Reason}
    end.

fetch_response(S0) ->
    case do_fetch_response(S0#?MODULE.socket, S0#?MODULE.parser, S0#?MODULE.rest) of
	{ok, Entity, NewParser} ->
	    S1 = S0#?MODULE{parser = NewParser, rest = <<>>},
	    {ok, Entity, S1};
	{ok, Entity, Rest, NewParser} ->
	    S1 = S0#?MODULE{parser = NewParser, rest = Rest},
	    {ok, Entity, S1}
    end.

do_fetch_response(Socket, Parser, <<>>) ->
    {ok, Data} = gen_tcp:recv(Socket, 0),
    do_fetch_response(Socket, Parser, Data);

do_fetch_response(Socket, Parser0, Data) ->
    case eredis_parser:parse(Parser0, Data) of
	{ok, Entity, Parser1} ->
	    {ok, decode_response_entity(Entity), Parser1};
	{ok, Entity, Rest, Parser1} ->
	    {ok, decode_response_entity(Entity), Rest, Parser1};
	{continue, Parser1} ->
	    do_fetch_response(Socket, Parser1, <<>>)
    end.

decode_response_entity([<<"subscribe">>, Channel, CountBin]) ->
    {subscribe, Channel, erlang:binary_to_integer(CountBin)};

decode_response_entity([<<"psubscribe">>, Channel, CountBin]) ->
    {psubscribe, Channel, erlang:binary_to_integer(CountBin)};

decode_response_entity([<<"unsubscribe">>, Channel, CountBin]) ->
    {unsubscribe, Channel, erlang:binary_to_integer(CountBin)};

decode_response_entity([<<"punsubscribe">>, Channel, CountBin]) ->
    {punsubscribe, Channel, erlang:binary_to_integer(CountBin)};

decode_response_entity([<<"message">>, Channel, Content]) ->
    {message, Channel, Content}.
