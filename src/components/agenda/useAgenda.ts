import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

export type AgendaRow = Database["public"]["Tables"]["agenda_events"]["Row"];
export type AgendaKind = Database["public"]["Enums"]["agenda_kind"];

type Client = SupabaseClient<Database>;

export const AGENDA_KIND_LABEL: Record<AgendaKind, string> = {
  homework: "واجب منزلي",
  evaluation: "تقييم",
};

/** yyyy-mm-dd in local time (matches the `date` column). */
export function toDateKey(date: Date) {
  const y = date.getFullYear();
  const m = `${date.getMonth() + 1}`.padStart(2, "0");
  const d = `${date.getDate()}`.padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function shiftDay(key: string, days: number) {
  const [y, m, d] = key.split("-").map(Number);
  const date = new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
  date.setDate(date.getDate() + days);
  return toDateKey(date);
}

export function formatDayLabel(key: string) {
  const [y, m, d] = key.split("-").map(Number);
  const date = new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
  return date.toLocaleDateString("ar-MA", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

export function useAgenda(
  client: Client,
  filter: { classId?: string | null; teacherId?: string },
  dateKey: string,
) {
  const [rows, setRows] = useState<AgendaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { classId, teacherId } = filter;

  const load = useCallback(async () => {
    if (classId === null) {
      setRows([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    let query = client
      .from("agenda_events")
      .select("*")
      .eq("event_date", dateKey)
      .order("created_at", { ascending: true });
    if (classId) query = query.eq("class_id", classId);
    if (teacherId) query = query.eq("teacher_id", teacherId);
    const { data, error: err } = await query;
    if (err) {
      setError("تعذّر تحميل المفكرة.");
      setRows([]);
    } else {
      setError(null);
      setRows(data ?? []);
    }
    setLoading(false);
  }, [client, classId, teacherId, dateKey]);

  useEffect(() => {
    void load();
  }, [load]);

  return { rows, loading, error, setError, reload: load };
}
