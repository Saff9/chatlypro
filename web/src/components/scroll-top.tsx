"use client";

export default function ScrollTop() {
  return (
    <button
      onClick={() => window.scrollTo({ top: 0, behavior: "smooth" })}
      className="fixed bottom-6 right-6 w-12 h-12 bg-primary clip-triangle flex items-center justify-center text-black"
    >
      ▲
    </button>
  );
}
