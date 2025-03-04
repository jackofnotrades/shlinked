defmodule ShlinkedinWeb.ProfileLive.Show do
  use ShlinkedinWeb, :live_view
  alias Shlinkedin.Timeline
  alias Shlinkedin.Timeline.Comment
  alias Shlinkedin.Profiles
  alias Shlinkedin.Profiles.{Endorsement, Testimonial}
  alias Shlinkedin.Points.Transaction
  alias Shlinkedin.Ads
  alias Shlinkedin.{Chat, Chat.Conversation}

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    if connected?(socket) do
      Timeline.subscribe()
    end

    show_profile = Shlinkedin.Profiles.get_profile_by_slug(slug)

    socket = is_user(session, socket)

    # store profile view
    Profiles.create_profile_view(socket.assigns.profile, show_profile)

    {:ok,
     socket
     |> assign(show_profile: show_profile)
     |> assign(
       like_map: Timeline.like_map(),
       comment_like_map: Timeline.comment_like_map(),
       page: 1,
       per_page: 5,
       num_show_comments: 1
     )
     |> assign(live_action: socket.assigns.live_action || :show)
     |> assign(page_title: "ShlinkedIn - " <> show_profile.persona_name)
     |> assign(content_selection: "about")
     |> assign(from_notifications: false)
     |> assign(current_awards: Profiles.list_awards(show_profile))
     |> assign(award_types: Shlinkedin.Awards.list_award_types())
     |> assign(ad_clicks: list_unique_ad_clicks(show_profile))
     |> fetch_posts()
     |> assign(from_profile: socket.assigns.profile)
     |> assign(to_profile: show_profile)
     |> assign(connections: Profiles.get_connections(show_profile))
     |> assign(friend_status: check_between_friend_status(socket.assigns.profile, show_profile))
     |> assign(endorsements: list_endorsements(show_profile.id))
     |> assign(mutual_friends: get_mutual_friends(socket.assigns.profile, show_profile))
     |> assign(reviews_recieved: true)
     |> assign(number_testimonials: Profiles.get_number_testimonials(show_profile.id))
     |> assign(number_given_testimonials: Profiles.get_number_given_testimonials(show_profile.id))
     |> assign(num_show_testimonials: 2)
     |> assign(checklist: Shlinkedin.Levels.get_current_checklist(show_profile, socket))
     |> assign(num_profile_views: Profiles.get_profile_views_not_yourself(show_profile))
     |> assign(wealth_ranking: Profiles.get_ranking(show_profile, 50, "Wealth"))
     |> assign(stuff: Ads.list_owned_ads(show_profile))
     |> assign(testimonials: list_testimonials(show_profile.id)), temporary_assigns: [posts: []]}
  end

  defp fetch_posts(%{assigns: %{show_profile: show_profile, page: page, per_page: per}} = socket) do
    assign(socket,
      posts:
        Timeline.list_posts(show_profile, [paginate: %{page: page, per_page: per}], "profile")
    )
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :from_notifications, _params) do
    socket
    |> assign(:from_notifications, true)
  end

  defp apply_action(socket, :edit_endorsement, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Endorsement")
    |> assign(:endorsement, Profiles.get_endorsement!(id))
  end

  defp apply_action(socket, :edit_testimonial, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Review")
    |> assign(:testimonial, Profiles.get_testimonial!(id))
  end

  defp apply_action(socket, :new_endorsement, %{"slug" => slug}) do
    socket
    |> assign(:page_title, "Endorse #{socket.assigns.show_profile.persona_name}")
    |> assign(:from_profile, socket.assigns.profile)
    |> assign(:to_profile, Profiles.get_profile_by_slug(slug))
    |> assign(:endorsement, %Endorsement{})
  end

  defp apply_action(socket, :new_testimonial, %{"slug" => slug}) do
    socket
    |> assign(:page_title, "Write a review for #{socket.assigns.show_profile.persona_name}")
    |> assign(:from_profile, socket.assigns.profile)
    |> assign(:to_profile, Profiles.get_profile_by_slug(slug))
    |> assign(:testimonial, %Testimonial{})
  end

  defp apply_action(socket, :new_transaction, %{"slug" => slug}) do
    socket
    |> assign(:page_title, "Send ShlinkPoints to #{socket.assigns.show_profile.persona_name}")
    |> assign(:from_profile, socket.assigns.profile)
    |> assign(:to_profile, Profiles.get_profile_by_slug(slug))
    |> assign(:transaction, %Transaction{})
  end

  defp apply_action(socket, :edit_awards, %{"slug" => slug}) do
    socket
    |> assign(:page_title, "Grant Award to #{socket.assigns.show_profile.persona_name}")
    |> assign(:from_profile, socket.assigns.profile)
    |> assign(:to_profile, Profiles.get_profile_by_slug(slug))
    |> assign(:awards, Shlinkedin.Awards.list_award_types())
    |> assign(:current_awards, Profiles.list_awards(socket.assigns.show_profile))
  end

  defp apply_action(socket, :show_likes, %{"post_id" => id}) do
    post = Timeline.get_post_preload_profile(id)

    socket
    |> assign(:page_title, "Reactions")
    |> assign(
      :grouped_likes,
      Timeline.list_likes(post)
      |> Enum.group_by(&%{name: &1.name, photo_url: &1.photo_url, slug: &1.slug})
    )
  end

  defp apply_action(socket, :show_comment_likes, %{"comment_id" => comment_id}) do
    comment = Timeline.get_comment!(comment_id)

    socket
    |> assign(:page_title, "Comment Reactions")
    |> assign(
      :grouped_likes,
      Timeline.list_comment_likes(comment)
      |> Enum.group_by(&%{name: &1.name, photo_url: &1.photo_url, slug: &1.slug})
    )
    |> assign(:comment, comment)
  end

  defp apply_action(socket, :new_comment, %{"post_id" => id, "reply_to" => username}) do
    post = Timeline.get_post_preload_profile(id)

    socket
    |> assign(:page_title, "Reply to #{post.profile.persona_name}'s comment")
    |> assign(:reply_to, username)
    |> assign(:comments, [])
    |> assign(:comment, %Comment{})
    |> assign(:post, post)
  end

  defp apply_action(socket, :new_comment, %{"post_id" => id}) do
    post = Timeline.get_post_preload_profile(id)

    socket
    |> assign(:page_title, "Comment")
    |> assign(:reply_to, nil)
    |> assign(:comments, [])
    |> assign(:comment, %Comment{})
    |> assign(:post, post)
  end

  defp apply_action(socket, :show_friends, _) do
    friends = Profiles.list_friends(socket.assigns.show_profile)

    socket
    |> assign(:page_title, "#{socket.assigns.show_profile.persona_name}'s Shlinks")
    |> assign(:friends, friends)
  end

  defp apply_action(socket, :show_ad_clicks, _) do
    socket
    |> assign(:page_title, "#{socket.assigns.show_profile.persona_name}'s Ad Clicks")
  end

  def handle_event("message", _, socket) do
    profile_ids = [socket.assigns.profile.id, socket.assigns.to_profile.id]

    profile_ids
    |> Enum.sort()
    |> Enum.map(&to_string/1)
    |> create_or_find_convo?()
    |> redirect_conversation(socket)
  end

  def handle_event("select-content", %{"content" => content}, socket) do
    case content do
      "posts" ->
        socket = assign(socket, content_selection: content, page: 1, per_page: 5) |> fetch_posts()
        {:noreply, socket}

      "ads" ->
        {:noreply,
         assign(socket,
           content_selection: content,
           ads: Shlinkedin.Ads.list_profile_ads(socket.assigns.show_profile)
         )}

      _ ->
        {:noreply, assign(socket, content_selection: content)}
    end
  end

  @impl true
  def handle_event("delete-profile", %{"id" => id}, socket) do
    profile = Profiles.get_profile_by_user_id(id)
    {:ok, _} = Profiles.delete_profile(profile)

    {:noreply, socket |> fetch_posts()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Timeline.get_post!(id)
    {:ok, _} = Timeline.delete_post(post)

    {:noreply, socket |> fetch_posts()}
  end

  @impl true
  def handle_event("delete-comment", %{"id" => id}, socket) do
    comment = Timeline.get_comment!(id)
    {:ok, _} = Timeline.delete_comment(comment)

    {:noreply,
     socket
     |> put_flash(:info, "Comment deleted")
     |> push_redirect(to: Routes.profile_show_path(socket, :show, socket.assigns.profile.slug))}
  end

  @impl true
  def handle_event("delete-endorsement", %{"id" => id}, socket) do
    endorsement = Profiles.get_endorsement!(id)
    {:ok, _} = Profiles.delete_endorsement(endorsement)

    {:noreply, assign(socket, :endorsements, list_endorsements(socket.assigns.to_profile.id))}
  end

  @impl true
  def handle_event("delete-testimonial", %{"id" => id}, socket) do
    testimonial = Profiles.get_testimonial!(id)
    {:ok, _} = Profiles.delete_testimonial(testimonial)

    {:noreply, assign(socket, :testimonials, list_testimonials(socket.assigns.to_profile.id))}
  end

  def handle_event("show-more-testimonials", _, socket) do
    socket = assign(socket, num_show_testimonials: socket.assigns.num_show_testimonials + 5)
    {:noreply, socket}
  end

  def handle_event("show-fewer-testimonials", _, socket) do
    socket = assign(socket, num_show_testimonials: 2)
    {:noreply, socket}
  end

  def handle_event("send-friend-request", _, socket) do
    Profiles.send_friend_request(socket.assigns.from_profile, socket.assigns.to_profile)
    status = check_between_friend_status(socket.assigns.profile, socket.assigns.to_profile)

    {:noreply,
     socket
     |> assign(friend_status: status)}
  end

  def handle_event("unfriend", _, socket) do
    Profiles.cancel_friend_request(socket.assigns.from_profile, socket.assigns.to_profile)
    status = check_between_friend_status(socket.assigns.profile, socket.assigns.to_profile)

    {:noreply,
     socket
     |> assign(friend_status: status)}
  end

  def handle_event("jab", _, socket) do
    if Profiles.count_jabs_in_timeframe(socket.assigns.profile) > 1 do
      {:noreply,
       socket
       |> put_flash(:warning, "You can only Jab once per 10min!")}
    else
      Profiles.send_jab(socket.assigns.from_profile, socket.assigns.to_profile)

      {:noreply,
       socket
       |> put_flash(:info, "Business Jabbed!")}
    end
  end

  def handle_event("load-more", _, %{assigns: assigns} = socket) do
    {:noreply, socket |> assign(page: assigns.page + 1) |> fetch_posts()}
  end

  def handle_event("show-received", _, socket) do
    socket =
      assign(socket,
        reviews_recieved: true,
        testimonials: list_testimonials(socket.assigns.show_profile.id)
      )

    {:noreply, socket}
  end

  def handle_event("show-given", _, socket) do
    socket =
      assign(socket,
        reviews_recieved: false,
        testimonials: list_given_testimonials(socket.assigns.show_profile.id)
      )

    {:noreply, socket}
  end

  defp list_endorsements(id) do
    Profiles.list_endorsements(id)
  end

  defp check_between_friend_status(from, to) do
    Profiles.check_between_friend_status(from, to)
  end

  defp list_testimonials(id) do
    Profiles.list_testimonials(id)
  end

  defp list_given_testimonials(id) do
    Profiles.list_given_testimonials(id)
  end

  defp get_mutual_friends(from, to) do
    Profiles.get_mutual_friends(from, to)
  end

  defp list_unique_ad_clicks(profile) do
    Shlinkedin.Ads.list_unique_ad_clicks(profile)
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    if post.profile.id == socket.assigns.profile.id do
      {:noreply, update(socket, :posts, fn posts -> [post | posts] end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_updated, post}, socket) do
    if post.profile.id == socket.assigns.profile.id do
      {:noreply, update(socket, :posts, fn posts -> [post | posts] end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_deleted, post}, socket) do
    if post.profile.id == socket.assigns.profile.id do
      {:noreply, update(socket, :posts, fn posts -> [post | posts] end)}
    else
      {:noreply, socket}
    end
  end

  defp create_or_find_convo?(profile_ids) when is_list(profile_ids) do
    case Chat.conversation_exists?(profile_ids) do
      %Conversation{} = convo ->
        {:ok, convo}

      nil ->
        %{
          "conversation_members" => conversation_members_format(profile_ids),
          "profile_ids" => profile_ids |> Enum.sort()
        }
        |> Chat.create_conversation()
    end
  end

  defp redirect_conversation({:ok, %Conversation{id: id}}, socket) do
    {:noreply,
     socket
     |> push_redirect(to: Routes.message_show_path(socket, :show, id))}
  end

  defp conversation_members_format(profile_ids) do
    profile_ids
    |> Enum.sort()
    |> Enum.with_index()
    |> Enum.map(fn {id, i} -> {to_string(i), %{"profile_id" => id}} end)
    |> Enum.into(%{})
  end
end
