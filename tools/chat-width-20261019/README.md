# Consistent chat bubble widths

Framework e41841b18, CSS-only follow-up to 8db5f86f6, Chisimba.com.
Every bubble uses the same available width minus 1rem, with border-box sizing.
Sender alignment creates a fixed small offset rather than shortening short replies.
Local 390px browser check measured all three bubbles at 301px and the sender offset
at 16px, with no horizontal overflow. Both consecutive own replies retained the
same width and alignment. No schema, database or module registration changes.
Deployment uses source hash checks, copied release, atomic symlink and web recreate;
its deployed.json records the release and rollback paths.
