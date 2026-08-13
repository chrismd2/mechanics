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
    get "/email/verify", AuthController, :verify_email
    get "/login", AuthController, :new_session
    post "/password/reset", AuthController, :request_password_reset
    get "/password/reset", AuthController, :new_password_reset
    post "/password/reset/confirm", AuthController, :confirm_password_reset
    post "/login", AuthController, :create_session
    delete "/logout", AuthController, :delete_user_session

    get "/account", AccountController, :show
    put "/account", AccountController, :update
    delete "/account", AccountController, :delete_account
    post "/account/become-mechanic", AccountController, :become_mechanic
    post "/account/password", AccountController, :update_password

    get "/disclaimer", PageController, :disclaimer

    get "/", PageController, :home
  end

  scope "/", MechanicsWeb do
    pipe_through :browser

    get "/profile", ProfileController, :show
    post "/profile", ProfileController, :save
    get "/listings/new", ListingController, :new
    post "/listings", ListingController, :create
    get "/listings/:id/edit", ListingController, :edit
    post "/listings/:id", ListingController, :update
    delete "/listings/:id", ListingController, :delete

    get "/pricing", PricingController, :index
    get "/pricing/queries", PricingController, :queries
    delete "/pricing/queries/:id", PricingController, :delete_query
    post "/pricing/queries/:id/similar/:market_price_id/dismiss",
         PricingController,
         :dismiss_similar
    post "/pricing/from-vin", PricingController, :lookup_from_vin
    get "/pricing/market-prices/new", PricingController, :new_market_price
    post "/pricing/market-prices/from-url", PricingController, :import_market_price_from_url
    post "/pricing/market-prices", PricingController, :create_market_price
    post "/pricing/suggest", PricingController, :suggest

    get "/admin", AdminController, :index
    post "/admin/auction-sources", AdminController, :create_source
    post "/admin/auction-sources/from-suggestion", AdminController, :create_source_from_suggestion
    patch "/admin/auction-sources/:id", AdminController, :update_source
    post "/admin/jobs/crawl", AdminController, :enqueue_crawl
    post "/admin/jobs/search", AdminController, :trial_search
    post "/admin/candidates/:id/digest", AdminController, :enqueue_digest
    post "/admin/candidates/:id/dismiss", AdminController, :dismiss_candidate

    get "/admin/auction-sources", Admin.AuctionSourcesController, :index
    get "/admin/jobs", Admin.JobsController, :index
    get "/admin/jobs/:id", Admin.JobsController, :show
    get "/admin/candidates", Admin.CandidatesController, :index
    get "/admin/candidates/:id", Admin.CandidatesController, :show

    get "/chats/open/mechanic/:mechanic_user_id", ChatController, :open_by_mechanic
    get "/chats/open/listing/:listing_id", ChatController, :open_by_listing
    get "/chats/open/listing_owner/:listing_id", ChatController, :open_listing_owner_next
    get "/chats/open/mechanic_pm_next", ChatController, :open_mechanic_pm_next
    post "/chats/:id/messages", ChatController, :create_message
    get "/chats/:id", ChatController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", MechanicsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Mix.env() == :dev and Application.compile_env(:mechanics, :dev_routes, false) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    pipeline :dev_routes do
      plug MechanicsWeb.Plugs.DevRoutes
    end

    scope "/dev" do
      pipe_through [:dev_routes, :browser]

      live_dashboard "/dashboard", metrics: MechanicsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/", MechanicsWeb do
    pipe_through :browser

    get "/*path", PageController, :redirect_home
  end
end
