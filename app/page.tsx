export default function Home() {
  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b px-6 py-4">
        <span className="text-lg font-semibold">Verkvis</span>
      </header>
      <main className="flex flex-1 items-center justify-center">
        <h1 className="text-3xl font-semibold">Hello World</h1>
      </main>
      <footer className="border-t px-6 py-4 text-sm text-zinc-500">
        © {new Date().getFullYear()} Verkvis
      </footer>
    </div>
  );
}
