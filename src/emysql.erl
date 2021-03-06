%% Copyright (c) 2009-2011
%% Bill Warnecke <bill@rupture.com>
%% Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% Patrick Atambo <partoa@gmail.com>
%%
%% Copyright (c) 2013
%%
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%%
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
%%==============================================================================
-module(emysql).

-export([start/0, stop/0]).
-export([
  add_pool/2, remove_pool/1,
  increment_pool_size/2, decrement_pool_size/2,
  query/2, query/3
]).

%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

%%------------------------------------------------------------------------------
start() ->
  crypto:start(),
  application:start(emysql).

%%------------------------------------------------------------------------------
stop() ->
  application:stop(emysql).

%%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

%%------------------------------------------------------------------------------
add_pool(PoolId, Props) when is_list(Props) ->
  {Size, Config} = emysql_app:pool_config(Props),
  emysql_conn_mgr:add_pool(PoolId, Size, Config).

%%------------------------------------------------------------------------------
remove_pool(PoolId) ->
  emysql_conn_mgr:remove_pool(PoolId).

%%------------------------------------------------------------------------------
increment_pool_size(PoolId, Num) when is_integer(Num) andalso Num >= 0 ->
  emysql_conn_mgr:open_connections(PoolId, Num).

%%------------------------------------------------------------------------------
decrement_pool_size(PoolId, Num) when is_integer(Num) andalso Num >= 0 ->
  emysql_conn_mgr:close_connections(PoolId, Num).

%%------------------------------------------------------------------------------
query(PoolId, Query) ->
  query(PoolId, Query, infinity).

%%------------------------------------------------------------------------------
query(PoolId, Query, Timeout) when
    is_list(Query) orelse is_binary(Query),
    is_integer(Timeout) andalso Timeout >= 0 orelse infinity =:= Timeout ->
  case emysql_conn_mgr:request_connection(PoolId, Timeout) of
    {ok, Connection} ->
      do_query(Connection, Query);
    unavailable ->
      {error, lock_timeout};
    Error ->
      Error
  end.
do_query(Connection, Query) ->
  try emysql_conn:query(Connection, Query) of
    Result ->
      emysql_conn_mgr:release_connection(Connection),
      Result
  catch
    {tcp, {_, closed}} ->
      case emysql_conn_mgr:renew_connection(Connection) of
        {ok ,NewConnection} ->
          do_query(NewConnection, Query);
        Error ->
          emysql_conn_mgr:release_connection(Connection),
          Error
      end;
    {tcp, Reason} ->
      emysql_conn:close(Connection),
      emysql_conn_mgr:release_connection(Connection),
      {error, Reason}
  end.
