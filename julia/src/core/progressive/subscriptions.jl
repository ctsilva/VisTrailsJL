"""
Subscriptions: per-consumer change tracking

Each consumer of a progressive container holds a subscription. The
container records every change into the buffers of all its subscriptions
when it happens, so each consumer reads, at its own pace, exactly what
changed since its own last read (ProgressiVis' change managers and
bookmarks, without a shared log).

Change combination, for a consumer that has not read a change yet:
- created, then updated → still created (it will read the new value);
- created, then deleted → nothing (it never saw the item);
- updated, then deleted → deleted.

Common interface, for every container type:
- `subscribe!(container)`: a new subscription; everything already in the
  container is reported as created;
- `has_changes(sub)`: whether unread changes are pending;
- `reset!(sub)`: drop pending changes and re-read everything as created;
- `unsubscribe!(sub)`: stop tracking.
"""

abstract type AbstractSubscription end

function subscribe! end
function has_changes end
function unsubscribe! end
