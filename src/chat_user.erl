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
            loop(Name)
    end.