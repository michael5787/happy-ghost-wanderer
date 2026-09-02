import { useEffect, useState } from "react";
import { Download, LinkIcon, Paperclip } from "lucide-react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import { openResource, type ResourceRow } from "@/components/resources/useResources";
import { AGENDA_KIND_LABEL, shiftDay, type AgendaRow } from "./useAgenda";

type Client = SupabaseClient<Database>;

/** Compte les entrées autour du jour affiché, pour marquer les jours du calendrier. */
export function useAgendaCounts(
  client: Client,
  filter: { classId?: string | null; teacherId?: string },
  dateKey: string,
  version: number,
) {
  const [counts, setCounts] = useState<Record<string, number>>({});
  const { classId, teacherId } = filter;

  useEffect(() => {
    if (classId === null) {
      setCounts({});
      return;
    }
    let active = true;
    (async () => {
      let query = client
        .from("agenda_events")
        .select("event_date")
        .gte("event_date", shiftDay(dateKey, -60))
        .lte("event_date", shiftDay(dateKey, 60));
      if (classId) query = query.eq("class_id", classId);
      if (teacherId) query = query.eq("teacher_id", teacherId);
      const { data } = await query;
      if (!active) return;
      const next: Record<string, number> = {};
      for (const row of data ?? []) next[row.event_date] = (next[row.event_date] ?? 0) + 1;
      setCounts(next);
    })();
    return () => {
      active = false;
    };
  }, [client, classId, teacherId, dateKey, version]);

  return counts;
}

/** Charge les ressources référencées par les entrées d'agenda. */
export function useAttachedResources(client: Client, rows: AgendaRow[]) {
  const ids = Array.from(new Set(rows.map((r) => r.resource_id).filter(Boolean) as string[]));
  const key = ids.join(",");
  const [map, setMap] = useState<Record<string, ResourceRow>>({});

  useEffect(() => {
    if (key === "") {
      setMap({});
      return;
    }
    let active = true;
    client
      .from("resources")
      .select("*")
      .in("id", key.split(","))
      .then(({ data }) => {
        if (!active) return;
        const next: Record<string, ResourceRow> = {};
        for (const r of data ?? []) next[r.id] = r;
        setMap(next);
      });
    return () => {
      active = false;
    };
  }, [client, key]);

  return map;
}

export function AgendaCard({
  client,
  row,
  resource,
  onError,
  actions,
}: {
  client: Client;
  row: AgendaRow;
  resource?: ResourceRow;
  onError: (msg: string) => void;
  actions?: React.ReactNode;
}) {
  const open = async (download: boolean) => {
    if (!resource) return;
    try {
      await openResource(client, resource, download);
    } catch {
      onError("تعذّر فتح الملف.");
    }
  };

  return (
    <article className="resource-card p-4 text-start">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span
            className={`rounded-full px-3 py-1 text-xs font-semibold ${
              row.kind === "evaluation"
                ? "bg-destructive/10 text-destructive"
                : "bg-primary/10 text-primary"
            }`}
          >
            {AGENDA_KIND_LABEL[row.kind]}
          </span>
          <h3 className="text-base font-semibold text-foreground">{row.title}</h3>
        </div>
        {actions}
      </div>

      {row.description ? (
        <p className="mt-3 whitespace-pre-wrap text-sm text-muted-foreground">{row.description}</p>
      ) : null}

      {resource ? (
        <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
          <Paperclip size={14} className="text-muted-foreground" />
          <span className="font-medium text-foreground">{resource.title}</span>
          <button type="button" className="btn-text" onClick={() => void open(false)}>
            فتح
          </button>
          <button type="button" className="btn-text" onClick={() => void open(true)}>
            <Download size={14} className="inline" /> تحميل
          </button>
        </div>
      ) : null}

      {row.link_url ? (
        <div className="mt-2 flex items-center gap-2 text-sm">
          <LinkIcon size={14} className="text-muted-foreground" />
          <a
            href={row.link_url}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-text"
            dir="ltr"
          >
            {row.link_url}
          </a>
        </div>
      ) : null}
    </article>
  );
}
