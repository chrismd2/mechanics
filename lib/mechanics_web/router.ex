defmodule MechanicsWeb.Router do
  use MechanicsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MechanicsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MechanicsWeb.Plugs.Authenticate
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MechanicsWeb do
    pipe_through :browser

    get "/register", AuthController, :new_registration
    post "/register", AuthController, :create_registration
    get "/login", AuthController, :new_session
    post "/password/reset", AuthController, :request_password_reset
    get "/password/reset", AuthController, :new_password_reset
    post "/password/reset/confirm", AuthController, :confirm_password_reset
    post "/login", AuthController, :create_session
    delete "/logout", AuthController, :delete_user_session

    get "/profile", ProfileController, :show
    get "/listings/new", ListingController, :new

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", MechanicsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mechanics, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MechanicsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
