defmodule ViewNinjasWeb.OfferLive do
  @moduledoc """
  The offer page (scope.md §11): three grade cards, a link field, a quantity, and
  a live total in whole shillings.

  The total is a promise, not a charge — there is no `add` and no money until M7.
  Continue records the "checkout started" step of the funnel and, signed out,
  sends the buyer to create an account. The link is untrusted input, so it goes
  through `ViewNinjas.Links` and no server-side fetch is ever made (§13).
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Catalog
  alias ViewNinjas.Catalog.{Grade, Lane}
  alias ViewNinjas.{Links, Pricing}
  alias ViewNinjasWeb.{Analytics, SEO}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:params, Pricing.current())
     |> assign(:offer, nil)
     |> assign(:grade, nil)
     |> assign(:paused, false)
     |> assign(:min, nil)
     |> assign(:max, nil)
     |> assign(:total, nil)
     |> assign(:quantity_error, nil)
     |> assign(:form, to_form(%{"link" => "", "quantity" => ""}, as: "order"))}
  end

  @impl true
  def handle_params(%{"id" => id}, uri, socket) do
    Analytics.record_page_view(socket, uri)

    case Catalog.get_market_offer(parse_id(id)) do
      nil -> {:noreply, to_market(socket)}
      offer -> {:noreply, load_offer(socket, offer, uri)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, to_market(socket)}

  @impl true
  def handle_event("choose", %{"grade" => grade}, socket) do
    with {:ok, grade} <- Grade.parse(grade),
         %{grade: ^grade} = lane <- selected_lane(socket.assigns.offer, grade) do
      {:noreply,
       socket
       |> assign(:grade, grade)
       |> assign(:paused, Lane.paused?(lane))
       |> assign_bounds(lane)
       |> preview()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update", %{"order" => params}, socket) do
    {:noreply,
     socket
     |> assign_form(Map.take(params, ["link", "quantity"]))
     |> preview()}
  end

  def handle_event("checkout", %{"order" => params}, socket) do
    lane = current_lane(socket)

    with :ok <- ensure_on_sale(lane),
         {:ok, link} <- Links.validate(params["link"]),
         {:ok, quantity} <- validate_quantity(params["quantity"], lane) do
      Analytics.record_event(socket, "/offers/#{socket.assigns.offer.id}/checkout")
      continue(socket, lane, link, quantity)
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section={:shop} title={@page_title}>
      <section :if={@offer} class="vn-card" id="offer">
        <h2>{@offer.title}</h2>
        <p :if={@offer.description} class="vn-muted">{@offer.description}</p>
        <p class="vn-muted">
          {gettext(
            "Buy %{title} in Kenya — priced in shillings and sold from your phone. Pick a grade, paste the link, choose how many, and pay by M-Pesa.",
            title: @offer.title
          )}
        </p>
      </section>

      <div :if={@offer} class="vn-grades-pick">
        <button
          :for={lane <- @offer.lanes}
          type="button"
          phx-click="choose"
          phx-value-grade={lane.grade}
          class={["vn-grade-card", @grade == lane.grade && "vn-grade-card--on"]}
          aria-pressed={to_string(@grade == lane.grade)}
          id={"pick-#{lane.grade}"}
        >
          <span class="vn-grade">{Grade.label(lane.grade)}</span>
          <span class="vn-price">{price_label(lane, @params)}</span>
          <span class="vn-muted">{meta_label(lane)}</span>
          <span :if={Lane.paused?(lane)} class="vn-error">{gettext("Paused")}</span>
        </button>
      </div>

      <p :if={@paused} class="vn-error" id="grade-paused">
        {gettext("This grade is paused while we top up the supplier. Please pick another.")}
      </p>

      <.form :if={@offer} for={@form} id="order-form" phx-change="update" phx-submit="checkout">
        <.input
          field={@form[:link]}
          label={gettext("The link to grow")}
          placeholder="https://instagram.com/yourhandle"
          autocomplete="off"
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label={gettext("How many")}
          min={@min}
          max={@max}
          inputmode="numeric"
        />
        <p class="vn-total" id="total">
          <span class="vn-muted">{gettext("Total")}</span>
          <span class="vn-total__value">{@total || "—"}</span>
        </p>
        <p :if={@quantity_error} class="vn-error" id="quantity-error">{@quantity_error}</p>
        <button class="vn-button" id="checkout" disabled={is_nil(@total) or @paused}>
          {gettext("Continue")}
        </button>
      </.form>

      <p :if={@offer} class="vn-muted">
        {gettext(
          "No charge yet — paying arrives with the next release. This total is a promise, not a payment."
        )}
      </p>

      <p :if={@offer} class="vn-muted">
        <.link navigate={~p"/refunds"} class="text-brand hover:underline" id="refund-link">
          {gettext("What if it does not fully arrive?")}
        </.link>
      </p>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load_offer(socket, offer, uri) do
    grade = default_grade(offer)
    lane = selected_lane(offer, grade)
    quantity = default_quantity(lane)
    canonical = SEO.canonical_url(uri)
    from = Catalog.from_selling_cents(offer, socket.assigns.params)

    socket
    |> assign(:page_title, offer.title)
    |> assign(:meta_title, offer_meta_title(offer, from))
    |> assign(:page_description, offer_description(offer, from))
    |> assign(:canonical_url, canonical)
    |> assign(:og_type, "product")
    |> assign(:structured_data, offer_structured_data(offer, socket.assigns.params, canonical))
    |> assign(:offer, offer)
    |> assign(:grade, grade)
    |> assign(:paused, Lane.paused?(lane))
    |> assign_bounds(lane)
    |> assign_form(%{"link" => "", "quantity" => Integer.to_string(quantity)})
    |> preview()
  end

  # -- search ------------------------------------------------------------

  # The offer is a platform and an outcome ("Instagram followers"), so the meta
  # title and description read as the buyer's query: "Buy Instagram followers in
  # Kenya", with the cheapest price when one is published.
  defp offer_meta_title(offer, nil), do: gettext("Buy %{title} in Kenya", title: offer.title)

  defp offer_meta_title(offer, cents) do
    gettext("Buy %{title} in Kenya — from %{price}",
      title: offer.title,
      price: Pricing.format_selling_cents(cents)
    )
  end

  defp offer_description(offer, nil) do
    gettext(
      "Buy %{title} in Kenya in three grades — cheap, moderate and quality. Priced in shillings, paid by M-Pesa, with a refill if delivery falls short.",
      title: offer.title
    )
  end

  defp offer_description(offer, cents) do
    gettext(
      "Buy %{title} in Kenya from %{price} per 1,000, in three grades. Priced in shillings, paid by M-Pesa, with a refill if delivery falls short.",
      title: offer.title,
      price: Pricing.format_selling_cents(cents)
    )
  end

  defp offer_structured_data(offer, params, canonical) do
    description = offer.description || offer_description(offer, nil)

    [
      SEO.product(%{
        name: offer.title,
        description: description,
        url: canonical,
        prices: published_shillings(offer, params)
      }),
      SEO.breadcrumbs([
        %{name: gettext("Shop"), url: SEO.absolutize("/shop")},
        %{name: offer.title, url: canonical}
      ])
    ]
  end

  defp published_shillings(offer, params) do
    offer.lanes
    |> Enum.map(&Lane.retail_kes_cents(&1, params))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&div(&1 + 50, 100))
  end

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: "order"))

  defp assign_bounds(socket, lane) do
    {min, max} = bounds(lane)
    assign(socket, min: min, max: max)
  end

  defp preview(socket) do
    case socket.assigns.form.params["quantity"] do
      value when value in [nil, ""] ->
        assign(socket, total: nil, quantity_error: nil)

      value ->
        case validate_quantity(value, current_lane(socket)) do
          {:ok, quantity} ->
            total = Lane.selling_cents(current_lane(socket), socket.assigns.params, quantity)

            assign(socket, total: Pricing.format_selling_cents(total), quantity_error: nil)

          {:error, message} ->
            assign(socket, total: nil, quantity_error: message)
        end
    end
  end

  defp continue(socket, lane, link, quantity) do
    if signed_in?(socket) do
      create_order(socket, lane, link, quantity)
    else
      {:noreply, push_navigate(socket, to: ~p"/users/register")}
    end
  end

  # Signed in, the order is created `awaiting_payment` and checkout takes over;
  # a guest is asked for an account first, and nothing is created for them.
  defp create_order(socket, lane, link, quantity) do
    attrs = %{
      user: socket.assigns.current_scope.user,
      lane: lane,
      link: link,
      quantity: quantity
    }

    case ViewNinjas.Orders.create_order(attrs) do
      {:ok, order} ->
        {:noreply, push_navigate(socket, to: ~p"/checkout/#{order.id}")}

      {:error, :lane_paused} ->
        {:noreply, put_flash(socket, :error, gettext("This grade is paused right now."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  defp to_market(socket) do
    socket
    |> put_flash(:error, gettext("That offer is not available."))
    |> push_navigate(to: ~p"/shop")
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp default_grade(offer) do
    if Enum.any?(offer.lanes, &(&1.grade == :cheap)) do
      :cheap
    else
      offer.lanes |> List.first() |> Map.fetch!(:grade)
    end
  end

  defp current_lane(socket), do: selected_lane(socket.assigns.offer, socket.assigns.grade)

  defp selected_lane(offer, grade), do: Enum.find(offer.lanes, &(&1.grade == grade))

  defp default_quantity(%{supplier_service: %{min: min, max: max}}) do
    cond do
      is_integer(min) and 1000 < min -> min
      is_integer(max) and 1000 > max -> max
      true -> 1000
    end
  end

  defp default_quantity(_lane), do: 1000

  defp bounds(%{supplier_service: %{min: min, max: max}}), do: {min, max}
  defp bounds(_lane), do: {nil, nil}

  defp validate_quantity(value, lane) when is_binary(value) do
    case Integer.parse(value) do
      {quantity, ""} -> check_bounds(quantity, lane)
      _ -> {:error, gettext("Enter how many you want as a whole number.")}
    end
  end

  defp validate_quantity(_value, _lane), do: {:error, gettext("Enter how many you want.")}

  defp check_bounds(quantity, lane) do
    {min, max} = bounds(lane)

    cond do
      quantity <= 0 ->
        {:error, gettext("Quantity must be more than zero.")}

      is_integer(min) and quantity < min ->
        {:error, gettext("This one starts at %{min}.", min: min)}

      is_integer(max) and quantity > max ->
        {:error, gettext("This one tops out at %{max}.", max: max)}

      true ->
        {:ok, quantity}
    end
  end

  defp ensure_on_sale(lane) do
    if Lane.on_sale?(lane), do: :ok, else: {:error, gettext("This grade is paused right now.")}
  end

  defp signed_in?(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{}} -> true
      _ -> false
    end
  end

  defp price_label(lane, params),
    do: Pricing.format_selling_cents(Lane.selling_cents(lane, params))

  defp meta_label(%{supplier_service: %{min: min, max: max, refill: refill}}) do
    bounds = if is_integer(min) and is_integer(max), do: "#{min}–#{max}", else: "—"
    if refill, do: bounds <> " · " <> gettext("Refill"), else: bounds
  end

  defp meta_label(_lane), do: "—"

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
