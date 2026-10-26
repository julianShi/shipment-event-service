(() => {
  const validStatuses = new Set(["created", "picked_up", "in_transit", "delivered", "failed"]);
  const statusLabels = {
    created: "Created",
    picked_up: "Picked up",
    in_transit: "In transit",
    delivered: "Delivered",
    failed: "Failed"
  };

  const referenceInput = document.getElementById("shipment-reference");
  const statusSelect = document.getElementById("event-status");
  const clearButton = document.getElementById("clear-filters");
  const retryButton = document.getElementById("retry-load");
  const table = document.getElementById("events-table");
  const tableBody = document.getElementById("events-body");
  const resultsSummary = document.getElementById("results-summary");
  const errorMessage = document.getElementById("error-message");

  let debounceTimer = null;
  let activeRequest = null;
  let lastQuery = null;

  function activeFilters() {
    return referenceInput.value.trim().length > 0 || statusSelect.value.length > 0;
  }

  function buildQuery() {
    const query = new URLSearchParams();
    const reference = referenceInput.value.trim();
    if (reference) query.set("shipment_reference", reference);
    if (statusSelect.value) query.set("status", statusSelect.value);
    return query;
  }

  function synchronizeUrl(query) {
    const suffix = query.toString();
    window.history.replaceState({}, "", suffix ? `/?${suffix}` : "/");
  }

  function updateClearButton() {
    clearButton.disabled = !activeFilters();
  }

  function renderStateRow(message) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.className = "table-state";
    cell.colSpan = 4;
    cell.textContent = message;
    row.appendChild(cell);
    tableBody.replaceChildren(row);
  }

  function appendCell(row, className, text) {
    const cell = document.createElement("td");
    if (className) cell.className = className;
    cell.textContent = text;
    row.appendChild(cell);
    return cell;
  }

  function formatTimestamp(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return value || "—";

    return new Intl.DateTimeFormat(undefined, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      timeZoneName: "short"
    }).format(date);
  }

  function renderEvents(events) {
    if (events.length === 0) {
      renderStateRow(activeFilters() ? "No events match these filters." : "No shipment events yet.");
      resultsSummary.textContent = activeFilters() ? "No matching events" : "No events found";
      return;
    }

    const rows = events.map((event) => {
      const row = document.createElement("tr");
      appendCell(row, "reference-cell", event.shipment_reference || "—");

      const statusCell = document.createElement("td");
      const pill = document.createElement("span");
      pill.className = "status-pill";
      pill.dataset.status = event.status || "";
      pill.textContent = statusLabels[event.status] || event.status || "Unknown";
      statusCell.appendChild(pill);
      row.appendChild(statusCell);

      const timestampCell = document.createElement("td");
      timestampCell.className = "timestamp-cell";
      const time = document.createElement("time");
      time.dateTime = event.event_timestamp || "";
      time.title = event.event_timestamp || "";
      time.textContent = formatTimestamp(event.event_timestamp);
      timestampCell.appendChild(time);
      row.appendChild(timestampCell);

      const idCell = appendCell(row, "event-id", event.event_id || "—");
      idCell.title = event.event_id || "";
      return row;
    });

    tableBody.replaceChildren(...rows);
    resultsSummary.textContent = `${events.length.toLocaleString()} ${events.length === 1 ? "event" : "events"} loaded`;
  }

  async function loadEvents({ updateUrl = true, force = false } = {}) {
    const query = buildQuery();
    const queryString = query.toString();
    if (updateUrl) synchronizeUrl(query);
    updateClearButton();
    if (!force && queryString === lastQuery) return;
    lastQuery = queryString;

    if (activeRequest) activeRequest.abort();
    const request = new AbortController();
    activeRequest = request;

    table.setAttribute("aria-busy", "true");
    errorMessage.hidden = true;
    retryButton.hidden = true;
    renderStateRow("Loading shipment events…");
    resultsSummary.textContent = "Loading shipment events…";

    const url = queryString ? `/shipment_events?${queryString}` : "/shipment_events";

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: request.signal
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Request failed");
      if (!payload || !Array.isArray(payload.events)) throw new Error("Unexpected response");
      renderEvents(payload.events);
    } catch (error) {
      if (error.name === "AbortError") return;
      renderStateRow("The events could not be loaded.");
      resultsSummary.textContent = "Request failed";
      errorMessage.textContent = "We could not load shipment events. Check the service and try again.";
      errorMessage.hidden = false;
      retryButton.hidden = false;
    } finally {
      if (activeRequest === request) {
        table.setAttribute("aria-busy", "false");
        activeRequest = null;
      }
    }
  }

  function restoreFiltersFromUrl() {
    const query = new URLSearchParams(window.location.search);
    referenceInput.value = query.get("shipment_reference") || "";
    const status = query.get("status") || "";
    statusSelect.value = validStatuses.has(status) ? status : "";
    updateClearButton();
  }

  referenceInput.addEventListener("input", () => {
    updateClearButton();
    window.clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(() => loadEvents(), 280);
  });

  referenceInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      window.clearTimeout(debounceTimer);
      loadEvents();
    }
  });

  statusSelect.addEventListener("change", () => {
    window.clearTimeout(debounceTimer);
    loadEvents();
  });
  clearButton.addEventListener("click", () => {
    window.clearTimeout(debounceTimer);
    referenceInput.value = "";
    statusSelect.value = "";
    loadEvents();
    referenceInput.focus();
  });
  retryButton.addEventListener("click", () => loadEvents({ force: true }));
  window.addEventListener("popstate", () => {
    restoreFiltersFromUrl();
    loadEvents({ updateUrl: false });
  });

  restoreFiltersFromUrl();
  loadEvents();
})();
