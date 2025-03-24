
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)
defmodule AppendEntries do


  ### Functions for receiving an append entries request (heartbeat or log entry)

  def receive_req(server, term, prev_index, prev_term, entries, commit_index, from) do
    server
      |> check_role_and_term(term)
      |> process_request(term, prev_index, prev_term, entries, commit_index, from)
      |> State.commit_index(commit_index)
      |> apply_entries()
  end

  # Checks the role and term of the server and steps down if necessary (disregards requests from old terms)
  defp check_role_and_term(server, term) do
    cond do
      term > server.curr_term or (server.role == :CANDIDATE and term == server.curr_term) ->
        server |> ServerLib.stepdown(term)
      term == server.curr_term ->
        server |> Timer.restart_election_timer()
      true -> server
    end
  end

  # Adds to the log and updates the commit index if the request is valid, then sends a reply
  defp process_request(server, term, prev_index, prev_term, entries, commit_index, from) do
    if term < server.curr_term do
      send from, {:APPEND_ENTRIES_REPLY, server.curr_term, false, -1, server.selfP}
      server
    else
      success = request_is_valid(server, prev_index, prev_term)
      {server, match_index} = get_updated_server_and_match_index(server, success, prev_index, entries, commit_index, from)
      send from, {:APPEND_ENTRIES_REPLY, server.curr_term, success, match_index, server.selfP}
      server
    end
  end

  # Updates the server returns the new match index if the request is valid
  defp get_updated_server_and_match_index(server, false, _, _, _, _), do: {server, -1}
  defp get_updated_server_and_match_index(server, true, prev_index, entries, commit_index, from) do
    State.leaderP(server, from) |> Log.store_entries(prev_index, entries, commit_index)
  end

  # Checks if the append_entries request is valid
  defp request_is_valid(_server, 0, _prev_term), do: true
  defp request_is_valid(server, prev_index, prev_term) do
    prev_index <= Log.last_index(server) and Log.term_at(server, prev_index) == prev_term
  end

  ### Functions for receiving an append entries reply

  def receive_reply(server, term, success, match_index, from) do
    if term > server.curr_term do
      server |> ServerLib.stepdown(term)
    else
      process_reply(server, server.role, term, server.curr_term, success, match_index, from)
    end
  end

  defp process_reply(server, :LEADER, serv_curr_term, serv_curr_term, success, match_index, from) do
    server = update_indices_and_commit(server, success, match_index, from)
    if server.next_index[from] <= Log.last_index(server) do
      server |> ServerLib.send_append_entries(from)
    else
      server
    end
  end
  defp process_reply(server, _role, _term, _serv_curr_term, _success, _match_index, _from), do: server
  # Not leader or old reply so disregard ^

  # Update the server, commit and match index if the reply is valid
  defp update_indices_and_commit(server, false, _match_index, from) do
    server |> State.next_index(from, max(1, server.next_index[from] - 1))
  end
  defp update_indices_and_commit(server, true, match_index, from) do
    server = server |> State.match_index(from, match_index) |> State.next_index(from, match_index + 1)
    if match_index > server.commit_index do
      server |> update_commit(match_index)
    else
      server
    end
  end

  defp update_commit(server, index_to_match) do
    #store old commit index
    old_commit_index = server.commit_index

    values = Enum.filter(Map.values(server.match_index), fn x -> x >= index_to_match end)
    server = if length(values) >= server.majority and Log.term_at(server, index_to_match) == server.curr_term do

      for i <- old_commit_index + 1 .. index_to_match do
        entry = Log.entry_at(server, i)
        send entry.clientP, {:CLIENT_REPLY, %{cid: entry.cid, reply: :LEADER, leaderP: server.leaderP}}
      end

      # Update monitor and commit index
      server |> State.commit_index(index_to_match)
    else
      server
    end
    server |> apply_entries()
  end


  ### Function for sending to the database

  defp apply_entries(server) do
    if server.commit_index > server.last_applied do
      entry = Log.entry_at(server, server.last_applied + 1)
      send server.databaseP, {:DB_REQUEST, entry}

      # if server.server_num == 1 do
      #   Process.exit(server.selfP, :normal)
      # end

      server = server |> State.last_applied(server.last_applied + 1)
      Debug.message(server, "+dreq", "Applied entry #{inspect(entry)}", 2)
      server |> apply_entries()
    else
      server
    end
  end


  ### Function for broadcasting append entries

  def broadcast_append_entries(server, 0), do: server # base case
  def broadcast_append_entries(server, num_servers_left) do
    receiver = Enum.at(server.servers, num_servers_left-1) # -1 as lists are 0 indexed
    server |> send_not_to_self(server.selfP, receiver) |> broadcast_append_entries(num_servers_left-1)
  end

  defp send_not_to_self(server, me, me), do: server
  defp send_not_to_self(server, _me, receiver) do
    server |> ServerLib.send_append_entries(receiver)
  end

end # AppendEntries
