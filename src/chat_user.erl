-module(chat_user).
-include("../include/chat.hrl").
-compile(export_all).

start(Name) ->
    spawn(?MODULE, init, [Name]).

init(Name) ->
    case chat_server:join(Name) of
        {ok, joined} ->
            io:format("User ~s joins.~n", [Name]),
            loop(Name);
        {error, username_taken} ->
            io:format("Username ~s is already taken.~n", [Name]);
        {error, timeout} ->
            io:format("Join timed out for ~s.~n", [Name])
    end.

loop(Name) ->
    receive
        {user_joined, OtherName} ->
            io:format("Server tells User ~s: User ~s has joined the room.~n", [Name, OtherName]),
            loop(Name);
        {user_disconnected, OtherName} ->
            io:format("Server tells User ~s: User ~s has disconnected.~n", [Name, OtherName]),
            loop(Name);
        leave ->
            request_leave(Name);
        {user_left, OtherName} ->
            io:format("Server tells User ~s: User ~s has left the room.~n", [Name, OtherName]),
            loop(Name);
        {message_from, Sender, Text} ->
            io:format("User ~s receives from ~s: ~s~n", [Name, Sender, Text]),
            loop(Name);
        {send_message, Text} ->
            request_send_message(Name, Text)
    end.

leave(UserPid) ->
    UserPid ! leave.

request_leave(Name) ->
    Ref = make_ref(),
    chat_server ! {self(), Ref, leave},
    receive
        {Ref, {ok, left}} ->
            exit(normal);
        {Ref, {error, not_found}} ->
            io:format("User ~s could not leave the room.~n", [Name]),
            loop(Name)
    after 5000 ->
        io:format("Leave timed out for ~s.~n", [Name]),
        loop(Name)
    end.

request_send_message(Name, Text) ->
    Ref = make_ref(),
    chat_server ! {self(), Ref, {message, Text}},
    receive
        {Ref, ok} ->
            loop(Name);
        {Ref, {error, not_registered}} ->
            io:format("User ~s is not registered.~n", [Name]),
            loop(Name)
    after 5000 ->
        io:format("Message send timed out for ~s.~n", [Name]),
        loop(Name)
    end.

send(UserPid, Text) ->
    UserPid ! {send_message, Text},
    ok.