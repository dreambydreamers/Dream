-- Help offer lifecycle: extend the status enum and link each offer to a conversation.
--
-- The "I can help" flow needs the full lifecycle (Pending, Accepted, Rejected,
-- In Progress, Completed, Cancelled). The original enum only had
-- pending/accepted/declined/withdrawn. We ADD the missing values rather than
-- recreate the type (which the dream_stats view depends on). Legacy `declined`
-- and `withdrawn` are kept but treated as rejected/cancelled in the app layer.
--
-- NOTE: new enum values can't be *referenced* in the same transaction that adds
-- them, so the partial unique index that prevents duplicate active offers (it
-- references 'in_progress') lives in 0009, which runs in a later transaction.

alter type help_offer_status add value if not exists 'rejected';
alter type help_offer_status add value if not exists 'in_progress';
alter type help_offer_status add value if not exists 'completed';
alter type help_offer_status add value if not exists 'cancelled';

-- Each help offer opens exactly one conversation between the supporter and the
-- dream owner. The FK constraint is added in 0009 once `conversations` exists.
alter table help_offers add column if not exists conversation_id uuid;
