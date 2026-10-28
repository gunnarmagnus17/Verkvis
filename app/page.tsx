// Forsíða: velja þjónustu og sjá verð og næsta lausa tíma hjá hverjum stað.
// Les beint úr gagnagrunninum í gegnum get_offers-fallið.
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

type Service = { code: string; name: string; category: string; unit: string | null };
type Slot = { id: string; starts_at: string; label: string | null };
type Offer = {
  shop_id: string;
  shop_name: string;
  area: string;
  external_url: string | null;
  price_isk: number;
  unit: string | null;
  avg_stars: number | null;
  review_count: number;
  next_slots: Slot[];
};

const SORTS = { price: "Ódýrast", time: "Fyrst laust" } as const;
type SortKey = keyof typeof SORTS;

const kr = (n: number) => n.toLocaleString("is-IS") + " kr.";
const when = (iso: string) =>
  new Date(iso).toLocaleString("is-IS", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Atlantic/Reykjavik",
  });

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ s?: string; rada?: string }>;
}) {
  const params = await searchParams;
  const service = params.s ?? "tires";
  const sort: SortKey = params.rada === "time" ? "time" : "price";

  const supabase = await createClient();
  const [servicesRes, offersRes] = await Promise.all([
    supabase.from("services").select("code, name, category, unit").order("category"),
    supabase.rpc("get_offers", { p_service: service }),
  ]);

  const services = (servicesRes.data ?? []) as Service[];
  const offers = ((offersRes.data ?? []) as Offer[]).slice();
  offers.sort((a, b) =>
    sort === "price"
      ? a.price_isk - b.price_isk
      : a.next_slots[0].starts_at.localeCompare(b.next_slots[0].starts_at)
  );
  const current = services.find((s) => s.code === service);

  return (
    <main style={{ maxWidth: 720, margin: "0 auto", padding: "24px 16px", fontFamily: "system-ui, sans-serif" }}>
      <h1 style={{ marginBottom: 4 }}>Verkvís</h1>
      <p style={{ marginTop: 0, color: "#56646B" }}>Berðu saman verð og næsta lausa tíma</p>

      <nav aria-label="Þjónusta" style={{ display: "flex", flexWrap: "wrap", gap: 8, margin: "16px 0" }}>
        {services.map((s) => (
          <Link
            key={s.code}
            href={`/?s=${s.code}&rada=${sort}`}
            aria-current={s.code === service ? "page" : undefined}
            style={{
              padding: "8px 12px",
              borderRadius: 999,
              border: "1px solid #D5DCE0",
              textDecoration: "none",
              color: s.code === service ? "#fff" : "#172126",
              background: s.code === service ? "#0F3B4C" : "transparent",
            }}
          >
            {s.name}
          </Link>
        ))}
      </nav>

      <h2>{current?.name ?? "Þjónusta"}</h2>
      <p>
        Raða:{" "}
        {(Object.keys(SORTS) as SortKey[]).map((k) => (
          <Link key={k} href={`/?s=${service}&rada=${k}`} style={{ marginRight: 12, fontWeight: k === sort ? 700 : 400 }}>
            {SORTS[k]}
          </Link>
        ))}
      </p>
      <p style={{ fontSize: 14, color: "#56646B" }}>
        Röðunin ræðst eingöngu af því sem þú velur. Enginn getur borgað sig ofar á listanum.
      </p>

      {offersRes.error && <p role="alert">Ekki tókst að sækja gögn. Reyndu aftur síðar.</p>}
      {!offersRes.error && offers.length === 0 && <p>Enginn staður hefur skráð verð og lausa tíma fyrir þessa þjónustu enn.</p>}

      {offers.map((o) => (
        <article key={o.shop_id} style={{ border: "1px solid #D5DCE0", borderRadius: 12, padding: 16, marginBottom: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
            <div>
              <strong>{o.shop_name}</strong>
              <div style={{ fontSize: 14, color: "#56646B" }}>
                {o.area}
                {o.avg_stars ? ` · ${o.avg_stars} ★ (${o.review_count})` : " · Engar umsagnir enn"}
              </div>
              <div style={{ marginTop: 6 }}>Næst laust: {when(o.next_slots[0].starts_at)}</div>
            </div>
            <div style={{ fontSize: 24, fontWeight: 700, whiteSpace: "nowrap" }}>
              {kr(o.price_isk)}
              {o.unit && <div style={{ fontSize: 13, fontWeight: 400 }}>{o.unit}</div>}
            </div>
          </div>
          <ul style={{ display: "flex", flexWrap: "wrap", gap: 8, listStyle: "none", padding: 0, margin: "12px 0 0" }}>
            {o.next_slots.map((s) => (
              <li key={s.id} style={{ border: "1px solid #0F3B4C", borderRadius: 8, padding: "6px 10px", fontSize: 14 }}>
                {when(s.starts_at)}
                {s.label ? ` · ${s.label}` : ""}
              </li>
            ))}
          </ul>
        </article>
      ))}
    </main>
  );
}
