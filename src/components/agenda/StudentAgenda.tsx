import { useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import { AgendaCalendar, formatDayLabelAr } from "./AgendaCalendar";
import { AgendaCard, useAgendaCounts, useAttachedResources } from "./agendaShared";
import { toDateKey, useAgenda } from "./useAgenda";

export function StudentAgenda({
  client,
  classId,
}: {
  client: SupabaseClient<Database>;
  classId: string | null;
}) {
  const [dateKey, setDateKey] = useState(() => toDateKey(new Date()));
  const { rows, loading, error, setError } = useAgenda(client, { classId }, dateKey);
  const counts = useAgendaCounts(client, { classId }, dateKey, 0);
  const resources = useAttachedResources(client, rows);

  return (
    <section>
      <h2 className="text-lg font-semibold text-foreground">المفكرة</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        الواجبات والتقييمات المبرمجة ليوم {formatDayLabelAr(dateKey)}.
      </p>

      <div className="mt-4">
        <AgendaCalendar value={dateKey} onChange={setDateKey} counts={counts} />
      </div>

      {error ? <p className="mt-4 text-sm text-destructive">{error}</p> : null}

      <div className="mt-6 space-y-3">
        {classId === null ? (
          <p className="text-sm text-muted-foreground">لم يتم تعيين قسم لحسابك بعد.</p>
        ) : loading ? (
          <p className="text-sm text-muted-foreground">جارٍ التحميل…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">لا توجد واجبات أو تقييمات في هذا اليوم.</p>
        ) : (
          rows.map((row) => (
            <AgendaCard
              key={row.id}
              client={client}
              row={row}
              {...(row.resource_id && resources[row.resource_id]
                ? { resource: resources[row.resource_id] }
                : {})}
              onError={setError}
            />
          ))
        )}
      </div>
    </section>
  );
}
