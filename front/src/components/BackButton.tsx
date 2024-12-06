"use client";

import { ArrowLeftFromLine } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";

export default function BackButton() {
  const router = useRouter();
  const pathName = usePathname();

  return pathName === "/" ? null : (
    <div
      onClick={() => router.push("/")}
      className="flex cursor-pointer justify-start fixed bg-black opacity-80 text-white p-4 m-6 rounded-md hover:bg-white hover:text-black "
    >
      <ArrowLeftFromLine />
    </div>
  );
}
