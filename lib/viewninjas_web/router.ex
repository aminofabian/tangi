defmodule ViewNinjasWeb.Router do
  use ViewNinjasWeb, :router

  import ViewNinjasWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug ViewNinjasWeb.Plugs.Referrer
    plug :fetch_live_flash
    plug :put_root_layout, html: {ViewNinjasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # The platform and uptime checks hit /health with no session and no
  # particular Accept header, so it runs through a deliberately empty
  # pipeline rather than :browser.
  pipeline :health do
  end

  # Provider callbacks (delivery reports) arrive as form posts with no session
  # and no particular Accept header, and must not be treated as browser traffic.
  pipeline :webhook do
  end

  # Crawler surfaces (`/robots.txt`, `/sitemap.xml`) are plain text and XML, so
  # they need no session, no CSRF token and no Accept negotiation.
  pipeline :crawler do
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ViewNinjasWeb do
    pipe_through :health

    get "/health", HealthController, :show
  end

  scope "/", ViewNinjasWeb do
    pipe_through :crawler

    get "/robots.txt", RobotsController, :index
    get "/sitemap.xml", SitemapController, :index
  end

  scope "/webhooks", ViewNinjasWeb do
    pipe_through :webhook

    post "/textsms/sms", SmsCallbackController, :text_sms
    post "/malipo", MalipoCallbackController, :create
  end

  # The public and signed-in app. Every page has the current scope mounted so
  # the shell can show who is signed in (scope.md §11, §12).
  scope "/", ViewNinjasWeb do
    pipe_through :browser

    live_session :app, on_mount: [{ViewNinjasWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive, :index
      live "/shop", HomeLive, :shop
      live "/offers/:id", OfferLive, :show
      live "/refunds", RefundsLive, :index
      live "/account", AccountLive, :index
      live "/blog", BlogLive, :index
      live "/blog/:slug", BlogLive, :show
    end
  end

  # The back office. Role-gated: `admin` and `super_admin` may enter, a signed
  # in customer is bounced to the shop, and a signed out visitor to log in.
  # The insight screens arrive in M10.
  scope "/", ViewNinjasWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin, on_mount: [{ViewNinjasWeb.UserAuth, :require_admin}] do
      live "/admin", Admin.DashboardLive, :index
      live "/admin/orders", Admin.OrdersLive, :index
      live "/admin/suppliers", Admin.SuppliersLive, :index
      live "/admin/catalog", Admin.CatalogLive, :index
    end
  end

  # The money knobs are the super-admin's alone (scope.md §7), so they live in
  # their own role-gated session: an ordinary admin is bounced to the shop.
  scope "/", ViewNinjasWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :super_admin, on_mount: [{ViewNinjasWeb.UserAuth, :require_super_admin}] do
      live "/admin/pricing", Admin.PricingLive, :index
      live "/admin/costs", Admin.CostsLive, :index
      live "/admin/insight", Admin.InsightLive, :index
      live "/admin/settlements", Admin.SettlementsLive, :index
      live "/admin/settings", Admin.SettingsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ViewNinjasWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:viewninjas, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ViewNinjasWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ViewNinjasWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ViewNinjasWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/verify-phone", UserLive.VerifyPhone, :new
      live "/checkout/:order_id", CheckoutLive, :show
      live "/wallet", WalletLive, :index
      live "/orders", OrdersLive, :index
      live "/orders/:id", OrderLive, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ViewNinjasWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ViewNinjasWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
