-module(natural_sort).


%% From Left Right Acc

copy_seq(FromFd, ToFd) ->
    case file:read_line(FromFd) of
    eof -> 
        eof;
    {ok, Str} ->
        file:write(ToFd, Str),
        copy_seq_(FromFd, ToFd, Str)
    end.


copy_seq_(FromFd, ToFd, LastStr) ->
    case file:read_line(FromFd) of
    {ok, Str} when LastStr < Str ->
        file:write(ToFd, Str),
        copy_seq_(FromFd, ToFd, Str);
    
    {ok, Str} ->
        file:position(FromFd, {cur, -byte_size(Str)});

    eof ->
        eof
    end.

append(FromFd, ToFd) ->
    case file:read_line(FromFd) of
    {ok, Str} ->
        file:write(ToFd, Str),
        append(FromFd, ToFd);

    eof ->
        eof
    end.


merge(LeftFd, RightFd, ToFd) ->
    io:format(user, "Left~n", []),
    dump_file(LeftFd),
    io:format(user, "Right~n", []),
    dump_file(RightFd),
    LeftStr = read_line(LeftFd),
    merge_(LeftFd, RightFd, ToFd, LeftStr, left).

read_line(Fd) ->
    case file:read_line(Fd) of
    {ok, Str} -> Str;
    eof -> eof
    end.

merge_(LeftFd, RightFd, ToFd, HigherStr, From) ->
    {LeftStr, RightStr} = 
    case From of
        left -> {HigherStr, read_line(RightFd)};
        right -> {read_line(LeftFd), HigherStr}
    end,

    if LeftStr =:= eof, RightStr =:= eof ->
            file:write(ToFd, HigherStr), 
            ok;
        LeftStr =:= eof ->
            file:write(ToFd, RightStr),
            append(RightFd, ToFd),
            ok;
        RightStr =:= eof ->
            file:write(ToFd, LeftStr),
            append(LeftFd, ToFd),
            ok;
        LeftStr < RightStr ->
            file:write(ToFd, LeftStr),
            merge_(LeftFd, RightFd, ToFd, RightStr, right);
        true ->
            file:write(ToFd, RightStr),
            merge_(LeftFd, RightFd, ToFd, LeftStr, left)
    end.



copy_and_merge(FromFd, ToFd, LeftFd, RightFd) ->
    case copy_seq(FromFd, LeftFd) of
        eof ->
            file:position(LeftFd, 0),
            append(LeftFd, ToFd),
            left_eof;
        _ ->
            Res = copy_seq(FromFd, RightFd),
            file:position(LeftFd, 0),
            file:position(RightFd, 0),
            merge(LeftFd, RightFd, ToFd),
            case Res of
                eof ->
                    right_eof;
                _ -> 
                    ok
            end
    end.

clean_and_copy_and_merge(FromFd, ToFd, LeftFd, RightFd) ->
    clean_and_copy_and_merge(FromFd, ToFd, LeftFd, RightFd, true).

clean_and_copy_and_merge(FromFd, ToFd, LeftFd, RightFd, First) ->
    clean(LeftFd),
    clean(RightFd),
    case copy_and_merge(FromFd, ToFd, LeftFd, RightFd) of
    left_eof when First -> 
    io:write(user, ok),
        ok;
    ok ->
        clean_and_copy_and_merge(FromFd, ToFd, LeftFd, RightFd, false);
    OtherEof ->
    io:format(user, "~p ~p~n", [First, OtherEof]),
        file:position(FromFd, 0),
        file:position(ToFd, 0),

        io:format(user, "From~n", []),
        dump_file(FromFd),
        io:format(user, "To~n", []),
        dump_file(ToFd),

        clean(FromFd),
        %% Swap ToFd with FromFd
        clean_and_copy_and_merge(ToFd, FromFd, LeftFd, RightFd, true)
    end.


dump_file(Fd) ->
    Pos = position(Fd),
    dump_file(Fd, Pos),
    io:format(user, "~n", []).

dump_file(Fd, Pos) ->
    case file:read_line(Fd) of
    {ok, Str} ->
        io:format(user, "~-10B: ~w~n", [position(Fd), Str]),
        dump_file(Fd, Pos);
    eof ->
        file:position(Fd, Pos)
    end.
    
position(Fd) ->
    {ok, Cur} = file:position(Fd, cur),
    Cur.

clean(Fd) ->
    file:position(Fd, 0),
%   io:write(user, file:read_line(Fd)),
    file:position(Fd, 0),
    file:truncate(Fd).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

simple_test_() ->
    {timeout, 50000, [fun() ->
    PartCount = 10,
    crypto:start(),
    Dir = mochitemp:mkdtemp(),
    TestDataFN = filename:join(Dir, testdata),

    %% Fill
    test_file(TestDataFN),
    Modes = [write, read, binary],
    {ok, FromFd}    = file:open(TestDataFN, Modes),
    {ok, ToFd}      = file:open(TestDataFN ++ ".to", Modes),
    {ok, LeftFd}    = file:open(TestDataFN ++ ".left", Modes),
    {ok, RightFd}   = file:open(TestDataFN ++ ".right", Modes),
    clean_and_copy_and_merge(FromFd, ToFd, LeftFd, RightFd),
    file:position(FromFd, 0),
    file:position(ToFd, 0),
    dump_file(FromFd),
    dump_file(ToFd),
    mochitemp:rmtempdir(Dir)
    end]}.
    

rand_line(Len) -> 
    Rand = crypto:rand_bytes(10),
    <<Rand/binary, $\n>>.

test_file(Name) ->
    {ok, FD} = file:open(Name, [write]),
    [file:write(FD,  rand_line(10)) || _ <- lists:seq(1, 15)],
    file:close(FD).


-endif.
