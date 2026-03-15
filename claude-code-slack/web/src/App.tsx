import { useEffect, useRef, useState } from "react";
import "./App.css";

interface Session {
  thread_ts: string;
  session_id: string;
  channel_id: string | null;
  slack_url: string | null;
  title: string | null;
}

function formatTs(ts: string): string {
  const epoch = parseFloat(ts) * 1000;
  if (isNaN(epoch)) return ts;
  const d = new Date(epoch);
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function EditableTitle({
  title,
  onSave,
}: {
  title: string;
  onSave: (newTitle: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(title);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setDraft(title);
    setEditing(false);
  }, [title]);

  useEffect(() => {
    if (editing) inputRef.current?.focus();
  }, [editing]);

  const save = () => {
    const trimmed = draft.trim();
    if (trimmed && trimmed !== title) {
      onSave(trimmed);
    }
    setEditing(false);
  };

  if (editing) {
    return (
      <input
        ref={inputRef}
        className="title-input"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={save}
        onKeyDown={(e) => {
          if (e.key === "Enter") save();
          if (e.key === "Escape") {
            setDraft(title);
            setEditing(false);
          }
        }}
      />
    );
  }

  return (
    <div className="title-row">
      <h2>{title}</h2>
      <button
        className="edit-btn"
        onClick={() => setEditing(true)}
        title="Rename"
        aria-label="Rename"
      >
        &#9998;
      </button>
    </div>
  );
}

function App() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/sessions")
      .then((r) => r.json())
      .then(setSessions)
      .catch(console.error);
  }, []);

  const active = sessions.find((s) => s.thread_ts === selected);

  const updateTitle = (threadTs: string, newTitle: string) => {
    fetch(`/api/sessions/${threadTs}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: newTitle }),
    })
      .then((r) => {
        if (!r.ok) throw new Error("Failed to update title");
        setSessions((prev) =>
          prev.map((s) =>
            s.thread_ts === threadTs ? { ...s, title: newTitle } : s
          )
        );
      })
      .catch(console.error);
  };

  return (
    <div className={`app ${selected ? "detail-open" : ""}`}>
      <aside className="sidebar">
        <h2>Recent Conversations</h2>
        <ul>
          {sessions.map((s) => (
            <li
              key={s.thread_ts}
              className={s.thread_ts === selected ? "active" : ""}
              onClick={() => setSelected(s.thread_ts)}
            >
              <span className="session-title">
                {s.title || s.session_id.slice(0, 8)}
              </span>
              <span className="session-date">{formatTs(s.thread_ts)}</span>
            </li>
          ))}
        </ul>
      </aside>
      <main className="content">
        {active ? (
          <div className="session-detail">
            <button className="back-btn" onClick={() => setSelected(null)}>
              &larr; Back
            </button>
            <EditableTitle
              title={active.title || "Untitled"}
              onSave={(t) => updateTitle(active.thread_ts, t)}
            />
            <dl>
              <dt>Date</dt>
              <dd>{formatTs(active.thread_ts)}</dd>
              <dt>Session ID</dt>
              <dd>{active.session_id}</dd>
              <dt>Channel ID</dt>
              <dd>{active.channel_id ?? "—"}</dd>
              <dt>Slack Thread</dt>
              <dd>
                {active.slack_url ? (
                  <a href={active.slack_url} target="_blank" rel="noreferrer">
                    {active.slack_url}
                  </a>
                ) : (
                  "No channel info"
                )}
              </dd>
            </dl>
          </div>
        ) : (
          <p className="placeholder">Select a conversation from the sidebar</p>
        )}
      </main>
    </div>
  );
}

export default App;
