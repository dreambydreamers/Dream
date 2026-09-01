-- 0033_fk_indexes.sql
-- Production-readiness audit (2026-08): covering indexes for foreign keys.
--
-- Every index here backs a foreign key that had none, which the Supabase
-- performance advisor flags: without them a referenced-row delete degrades to a
-- sequential scan of the referencing table, and the lookups below are on the
-- hot path.
--
--   * notifications(actor_id)          — ActivityRepository.load() resolves the
--                                        actor of every notification on open.
--   * messages(sender_id)              — ChatRepository.loadMessages() on every
--                                        chat open, plus profile cascades.
--   * messages(shared_dream_id/video)  — ChatRepository.loadSharePreviews().
--   * dream_comments/likes(video_id)   — clip delete cascades the whole thread
--                                        (0027/0028); unindexed that scans.

create index if not exists notifications_actor_idx
    on public.notifications (actor_id);
create index if not exists notifications_dream_idx
    on public.notifications (dream_id);
create index if not exists notifications_offer_idx
    on public.notifications (offer_id);
create index if not exists notifications_conversation_idx
    on public.notifications (conversation_id);

create index if not exists messages_sender_idx
    on public.messages (sender_id);
create index if not exists messages_shared_dream_idx
    on public.messages (shared_dream_id);
create index if not exists messages_shared_video_idx
    on public.messages (shared_video_id);

create index if not exists help_offers_conversation_idx
    on public.help_offers (conversation_id);

create index if not exists dream_comments_video_idx
    on public.dream_comments (video_id);

create index if not exists dream_likes_video_idx
    on public.dream_likes (video_id);

create index if not exists conversations_dream_idx
    on public.conversations (dream_id);
