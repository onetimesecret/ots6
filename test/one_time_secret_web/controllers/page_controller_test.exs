defmodule OneTimeSecretWeb.PageControllerTest do
  use OneTimeSecretWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Share a Secret"
  end
end
