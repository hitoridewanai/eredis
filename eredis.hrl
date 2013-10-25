%% @doc: Make the calling process the controlling process. The
%% controlling process received pubsub-related messages, of which
%% there are three kinds. In each message, the pid refers to the
%% eredis client process.
%%
%%   {message, Channel::binary(), Message::binary(), pid()}
%%     This is sent for each pubsub message received by the client.
%%
%%   {dropped, NumMessages::integer(), pid()}
%%     If the queue reaches the max size as specified in start_link
%%     and the behaviour is to drop messages, this message is sent when
%%     the queue is flushed.
%%
%%   {subscribed, Channel::binary(), pid()}
%%     When using eredis_sub:subscribe(pid()), this message will be
%%     sent for each channel Redis aknowledges the subscription. The
%%     opposite, 'unsubscribed' is sent when Redis aknowledges removal
%%     of a subscription.
%%
%%   {eredis_disconnected, pid()}
%%     This is sent when the eredis client is disconnected from redis.
%%
%%   {eredis_connected, pid()}
%%     This is sent when the eredis client reconnects to redis after
%%     an existing connection was disconnected.
%%
%% Any message of the form {message, _, _, _} must be acknowledged
%% before any subsequent message of the same form is sent. This
%% prevents the controlling process from being overrun with redis
%% pubsub messages. See ack_message/1.



%% Public types

-type reconnect_sleep() :: no_reconnect | integer().

-type option() :: {host, string()} | {port, integer()} | {database, string()} | {password, string()} | {reconnect_sleep, reconnect_sleep()}.
-type server_args() :: [option()].

-type return_value() :: undefined | binary() | [binary()].

-type pipeline() :: [iolist()].

-type channel() :: binary().

%% Continuation data is whatever data returned by any of the parse
%% functions. This is used to continue where we left off the next time
%% the user calls parse/2.
-type continuation_data() :: any().
-type parser_state() :: status_continue | bulk_continue | multibulk_continue.

%% Internal parser state. Is returned from parse/2 and must be
%% included on the next calls to parse/2.
-record(pstate, {
          state = undefined :: parser_state() | undefined,
          continuation_data :: continuation_data() | undefined
}).

-define(NL, "\r\n").

-define(SOCKET_OPTS, [binary, {active, once}, {packet, raw}, {reuseaddr, true}]).

-define(RECV_TIMEOUT, 5000).
