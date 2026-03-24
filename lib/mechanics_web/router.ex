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
    plug MechanicsWeb.Plugs.AssignDefaultLayout
    plug MechanicsWeb.Plugs.AssignChatNotifications
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MechanicsWeb do
    pipe_through :browser

    get "/altcha", AltchaController, :challenge
    get "/register", AuthController, :new_registration
    post "/register", AuthController, :create_registration
    get "/login", AuthController, :new_session
    post "/password/reset", AuthController, :request_password_reset
    get "/password/reset", AuthController, :new_password_reset
    post "/password/reset/confirm", AuthController, :confirm_password_reset
    post "/login", AuthController, :create_session
    delete "/logout", AuthController, :delete_user_session

    get "/account", AccountController, :show
    put "/account", AccountController, :update
    post "/account/become-mechanic", AccountController, :become_mechanic
    post "/account/password", AccountController, :update_password

    get "/profile", ProfileController, :show
    post "/profile", ProfileController, :save
    get "/listings/new", ListingController, :new
    post "/listings", ListingController, :create
    get "/listings/:id/edit", ListingController, :edit
    post "/listings/:id", ListingController, :update
    get "/disclaimer", PageController, :disclaimer

    get "/chats/open/mechanic/:mechanic_user_id", ChatController, :open_by_mechanic
    get "/chats/open/listing/:listing_id", ChatController, :open_by_listing
    get "/chats/open/listing_owner/:listing_id", ChatController, :open_listing_owner_next
    get "/chats/open/mechanic_pm_next", ChatController, :open_mechanic_pm_next
    post "/chats/:id/messages", ChatController, :create_message
    get "/chats/:id", ChatController, :show

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
