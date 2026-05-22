export default function Hero() {
  return (
    <section className="min-h-screen flex items-center justify-center pt-16">
      <div className="text-center max-w-2xl px-4">
        <h1 className="text-5xl font-bold mb-4">
          Hi, I’m <span className="text-primary">Owais</span>
        </h1>
        <p className="text-gray-400 mb-8">
          Building fast, modern web experiences.
        </p>
        <a
          href="#projects"
          className="inline-block px-6 py-3 rounded-full bg-primary text-black font-medium"
        >
          View My Work
        </a>
      </div>
    </section>
  );
}
