async function api(path, init) {
  const res = await fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", ...(init && init.headers ? init.headers : {}) },
    cache: "no-store",
  });
  if (!res.ok) throw new Error(await res.text());
  return await res.json();
}

function el(id) { return document.getElementById(id); }

function showErr(msg) {
  const box = el("err");
  if (!msg) { box.style.display = "none"; box.textContent = ""; return; }
  box.style.display = "block";
  box.textContent = msg;
}

function card(t, columns) {
  const c = document.createElement("div");
  c.className = "card";

  const top = document.createElement("div");
  top.className = "cardtop";

  const title = document.createElement("div");
  title.className = "title";
  title.textContent = t.title;

  const badge = document.createElement("div");
  badge.className = "badge";
  badge.textContent = t.priority || "medium";

  top.appendChild(title); top.appendChild(badge);
  c.appendChild(top);

  if (t.description) {
    const d = document.createElement("div");
    d.className = "desc";
    d.textContent = t.description;
    c.appendChild(d);
  }

  const meta = document.createElement("div");
  meta.className = "meta";
  meta.textContent = `Owner: ${t.owner || "—"} • ${new Date(t.createdAt).toLocaleString()}`;
  c.appendChild(meta);

  const actions = document.createElement("div");
  actions.className = "actions";

  const i = columns.findIndex(x => x.id === t.columnId);

  const left = document.createElement("button");
  left.textContent = "←";
  left.disabled = i <= 0;
  left.onclick = async () => {
    await api("/mc/api/tasks", { method: "PATCH", body: JSON.stringify({ id: t.id, patch: { columnId: columns[i-1].id } }) });
    await refresh();
  };

  const right = document.createElement("button");
  right.textContent = "→";
  right.disabled = i >= columns.length - 1;
  right.onclick = async () => {
    await api("/mc/api/tasks", { method: "PATCH", body: JSON.stringify({ id: t.id, patch: { columnId: columns[i+1].id } }) });
    await refresh();
  };

  const del = document.createElement("button");
  del.className = "danger";
  del.textContent = "Delete";
  del.onclick = async () => {
    await api("/mc/api/tasks", { method: "DELETE", body: JSON.stringify({ id: t.id }) });
    await refresh();
  };

  actions.appendChild(left); actions.appendChild(right); actions.appendChild(del);
  c.appendChild(actions);

  return c;
}

async function refresh() {
  showErr(null);
  const data = await api("/mc/api/tasks");
  const board = el("board");
  board.innerHTML = "";

  for (const col of data.columns) {
    const colEl = document.createElement("div");
    colEl.className = "col";

    const hdr = document.createElement("div");
    hdr.className = "colhdr";

    const h2 = document.createElement("h2");
    h2.textContent = col.name;

    const tasks = data.tasks.filter(t => t.columnId === col.id);

    const count = document.createElement("span");
    count.className = "count";
    count.textContent = tasks.length;

    hdr.appendChild(h2); hdr.appendChild(count);
    colEl.appendChild(hdr);

    const cards = document.createElement("div");
    cards.className = "cards";
    for (const t of tasks) cards.appendChild(card(t, data.columns));
    colEl.appendChild(cards);

    board.appendChild(colEl);
  }
}

async function addTask() {
  const title = el("title").value.trim();
  const description = el("desc").value.trim();
  const owner = el("owner").value.trim() || "Mitra";
  const priority = el("priority").value;

  if (!title) return;

  await api("/mc/api/tasks", {
    method: "POST",
    body: JSON.stringify({ title, description, owner, priority, columnId: "inbox", tags: ["growth"] }),
  });

  el("title").value = "";
  el("desc").value = "";
  await refresh();
}

el("refresh").onclick = () => refresh().catch(e => showErr(e.message));
el("add").onclick = () => addTask().catch(e => showErr(e.message));

refresh().catch(e => showErr(e.message));
