
# distributed algorithms, n.dulay, 14 jan 2024
# coursework, raft consensus, v2
# Preesha Gehlot (pg721) and Luc Lawford (ll4820)

defmodule Vote do

  def receive_vote_reply(server, term, vote, from) do
    Debug.message(server, "-vrep", {"Received vote reply from", from, "with term", term}, 2)
    server = if term > server.curr_term do
      ServerLib.stepdown(server, term)
    else
      server
    end

    #if you receive vote reply and you are the leader then what do you have to do
    if (term == server.curr_term) and (server.role == :CANDIDATE) do
      server
        |> add_voter(from, vote)
        |> Timer.cancel_append_entries_timer(from)
        |> majority()
    else
      server
    end
  end

  defp add_voter(server, from, vote) do
    if vote == server.selfP do
      server |> State.add_to_voted_by(from)
    else
      server
    end
  end


  defp majority(server) do
    if (State.vote_tally(server) >= server.majority) do
      server = server
              |> State.role(:LEADER)
              |> State.leaderP(server.selfP)
              |> State.init_next_index()
              |> State.init_match_index()

      Debug.message(server, "-vrep", "I am now the leader", 1)
      #Process.send_after(server.selfP, {:KILL}, server.config.crash_leaders_after)
      server |> AppendEntries.broadcast_append_entries(length(server.servers))
    else
      server
    end
  end


  def receive_vote_req(server, term, from, id, lastLogTerm, lastLogIndex) do
    Debug.message(server, "-vreq", {"Received vote request from", from, "with term", term}, 2)
    server =
      if term > server.curr_term do
        server |> ServerLib.stepdown(term)
      else
        server
      end

    latestLogIndex = Log.last_index(server)
    if (term == server.curr_term) and (server.voted_for == nil or server.voted_for == from)
    and ((lastLogTerm > Log.term_at(server, latestLogIndex))
          or (lastLogTerm == Log.term_at(server, latestLogIndex) and lastLogIndex >= latestLogIndex)) do
      server |> State.voted_for(from)
             |> Timer.restart_election_timer()
             |> Vote.reply_vote(term, from, id)
    else
      Debug.message(server, "-vreq", "Did not vote for #{id}", 2)
      server
    end
  end

  def reply_vote(server, term, from, id) do
    Debug.message(server, "+vrep", "Voted for #{id}", 2)
    send from, {:VOTE_REPLY, term, server.voted_for, server.selfP}
    server
  end

  def request_vote(server, term, follower, lastLogTerm, lastLogIndex) do
    Debug.message(server, "+vreq", {"Sending vote request to", follower}, 2)
    send follower, {:VOTE_REQUEST, term, server.selfP, server.server_num, lastLogTerm, lastLogIndex}
    server
  end

end # Vote
