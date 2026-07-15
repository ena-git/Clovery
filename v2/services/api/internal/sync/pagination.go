package sync

func BuildPullPage(changes []Change, limit int, currentCursor int64) PullPage {
	if limit < 1 {
		limit = 1
	}
	hasMore := len(changes) > limit
	if hasMore {
		changes = changes[:limit]
	}
	page := PullPage{
		Changes:    append([]Change(nil), changes...),
		NextCursor: currentCursor,
		HasMore:    hasMore,
	}
	if len(changes) > 0 {
		page.NextCursor = changes[len(changes)-1].Cursor
	}
	return page
}
