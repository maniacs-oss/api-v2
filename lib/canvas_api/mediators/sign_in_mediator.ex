defmodule CanvasAPI.SignInMediator do
  @moduledoc """
  Handle a Slack sign in, creating teams, accounts, and users as needed.
  """

  alias CanvasAPI.{Account, Repo, Team, User, UserService}
  alias CanvasAPI.WhitelistedSlackDomain, as: SlackDomain
  import Ecto.Changeset
  import Ecto.Query

  @client_id System.get_env("SLACK_CLIENT_ID")
  @client_secret System.get_env("SLACK_CLIENT_SECRET")
  @redirect_uri System.get_env("REDIRECT_URI")

  @doc """
  Sign in a user given a Slack OAuth exchange code.
  """
  @spec sign_in(String.t, Keyword.t) :: {:ok, Account.t} | {:error, any}
  def sign_in(code, account: account) do
    with {:ok, info} <- exchange_code(code, @redirect_uri) do
      ensure_account_in_team(account, info)
    end
  end

  # Ensure an account is in a given team.
  @spec ensure_account_in_team(Account.t | nil, map) :: {:ok, Account.t}
  defp ensure_account_in_team(account, info) do
    %{"access_token" => token,
      "team" => team_info,
      "user" => user_info} = info

    Repo.transaction(fn ->
      with {:ok, team} <- find_or_insert_team(team_info),
           {:ok, account} <- find_or_insert_account(account, user_info),
           {:ok, _} <- find_or_insert_user(account, team, user_info, token),
           {:ok, _} <- find_or_insert_personal_team(account) do
        account
      else
        {:error, error} -> Repo.rollback(error)
        error -> Repo.rollback(error)
      end
    end)
  end

  # Exchange Slack code for Slack information.
  @spec exchange_code(String.t, String.t) :: {:ok, map} | {:error, any}
  defp exchange_code(code, redirect_uri) do
    Slack.OAuth.access(client_id: @client_id,
                       client_secret: @client_secret,
                       code: code,
                       redirect_uri: redirect_uri)
  end

  # Find or insert an account from user info.
  @spec find_or_insert_account(Account.t | nil, map) ::
        {:ok, Account.t} | {:error, any}
  defp find_or_insert_account(account = %Account{}, _), do: {:ok, account}
  defp find_or_insert_account(nil, user_info) do
    find_user =
      from(u in User, where: u.slack_id == ^user_info["id"])
      |> preload(:account)

    with nil <- Repo.one(find_user),
         changeset = Account.changeset(%Account{}) do
      Repo.insert(changeset)
    else
      user = %User{} -> {:ok, user.account}
    end
  end

  # Find or insert an account's personal team.
  @spec find_or_insert_personal_team(Account.t) :: {:ok, Team.t} | {:error, any}
  defp find_or_insert_personal_team(account) do
    find_team =
      from(t in Ecto.assoc(account, :teams),
           where: is_nil(t.slack_id))
      |> Repo.one
    team_params = %{domain: "", name: ""}
    user_params =
      %{email: "account-#{account.id}@usecanvas.com",
        name: "Canvas User"}

    with nil <- find_team,
         changeset = Team.changeset(%Team{}, team_params)
                     |> put_change(:domain, "")
                     |> put_change(:name, ""),
         {:ok, team} <- Repo.insert(changeset),
         {:ok, _}
           <- UserService.insert(user_params, account: account, team: team) do
      {:ok, team}
    else
      team = %Team{} -> {:ok, team}
      error -> error
    end
  end

  # Find or insert a team from team info.
  @spec find_or_insert_team(map) :: {:ok, Team.t} | {:error, any}
  defp find_or_insert_team(team_info) do
    find_team = from(t in Team, where: t.slack_id == ^team_info["id"])
    team_params = team_info |> Map.put("slack_id", team_info["id"])

    with :ok <- check_domain_whitelist(team_info["domain"]),
         nil <- Repo.one(find_team),
         changeset = Team.changeset(%Team{}, team_params) do
      Repo.insert(changeset)
    else
      team = %Team{} -> {:ok, team}
      error -> error
    end
  end

  # Check a domain against the whitelist.
  @spec check_domain_whitelist(String.t) :: :ok | {:error, String.t}
  defp check_domain_whitelist(nil), do: {:error, "No domain provided"}
  defp check_domain_whitelist(domain) do
    from(d in SlackDomain, where: d.domain == ^domain)
    |> Repo.one
    |> case do
      nil ->
        {:error, "Domain not whitelisted"}
      _ ->
        :ok
    end
  end

  # Find or insert a user from team and user info.
  @spec find_or_insert_user(Account.t, Team.t, map, String.t) ::
        {:ok, User.t} | {:error, any}
  defp find_or_insert_user(account, team, user_info, token) do
    find_user =
      from(u in User,
           where: u.slack_id == ^user_info["id"],
           where: u.team_id == ^team.id)

    user_params =
      user_info
      |> Map.put("slack_id", user_info["id"])
      |> Map.put("identity_token", token)

    with nil <- Repo.one(find_user) do
      UserService.insert(user_params, account: account, team: team)
    else
      user = %User{} -> {:ok, user}
    end
  end
end
