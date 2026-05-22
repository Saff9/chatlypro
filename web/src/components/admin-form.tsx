"use client";

import { useState } from "react";

export default function AdminForm({
  onSubmit,
  fields
}: {
  onSubmit: (data: any) => void;
  fields: { name: string; placeholder: string }[];
}) {
  const [form, setForm] = useState<any>({});

  return (
    <form
      className="space-y-4 max-w-md"
      onSubmit={e => {
        e.preventDefault();
        onSubmit(form);
      }}
    >
      {fields.map(f => (
        <input
          key={f.name}
          placeholder={f.placeholder}
          className="w-full px-4 py-2 bg-black border border-white/10 rounded"
          onChange={e =>
            setForm({ ...form, [f.name]: e.target.value })
          }
        />
      ))}
      <button className="px-6 py-2 bg-primary text-black rounded">
        Save
      </button>
    </form>
  );
}
