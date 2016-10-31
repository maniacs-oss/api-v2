defmodule CanvasAPI.TeamServiceTest do
  use CanvasAPI.ModelCase

  alias CanvasAPI.TeamService, as: Service
  import CanvasAPI.Factory

  describe ".list" do
    setup do
      insert(:team)
      user = insert(:user)
      user2 = insert(:user, account: user.account)
      {:ok, user: user, user2: user2}
    end

    test "returns the teams for the given account", context do
      teams = Service.list(context.user.account, [])
      assert teams |> Enum.map(& &1.id) |> Enum.sort ==
        [context.user.team, context.user2.team]
        |> Enum.map(& &1.id)
        |> Enum.sort
    end

    test "returns filtered teams", context do
      team2 = context.user2.team
      teams = Service.list(context.user.account,
                           [filter: %{"domain" => team2.domain}])
      assert teams == [Repo.preload(team2, [:oauth_tokens])]
    end
  end

  describe ".show" do
    test "returns the team by ID when found" do
      team = insert(:team)
      assert Service.show(team.id) == {:ok, Repo.preload(team, [:oauth_tokens])}
    end

    test "returns the team by domain when found" do
      team = insert(:team)
      assert Service.show(team.domain) ==
        {:ok, Repo.preload(team, [:oauth_tokens])}
    end

    test "returns not_found when not found by ID" do
      assert Service.show(Ecto.UUID.generate) == {:error, :not_found}
    end

    test "returns not_found when not found by domain" do
      assert Service.show("foo") == {:error, :not_found}
    end
  end

  describe ".add_account_user" do
    test "adds the user when one exists" do
      user = insert(:user)
      team = Service.add_account_user(user.team, user.account)
      assert team.account_user.id == user.id
    end

    test "adds nil when no user exists" do
      user = insert(:user)
      team = Service.add_account_user(user.team, insert(:account))
      assert team.account_user == nil
    end

    test "adds nil when given no account" do
      user = insert(:user)
      team = Service.add_account_user(user.team, nil)
      assert team.account_user == nil
    end
  end
end