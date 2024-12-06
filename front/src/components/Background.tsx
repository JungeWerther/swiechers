import Image from "next/image";

export default function BackGround() {
  return (
    <div className="w-screen h-screen fixed top-0 inset-0 z-[-1]">
      <Image
        src="/headshot.jpg"
        alt="hero"
        width={0}
        height={0}
        sizes="100vw"
        className="h-full w-full object-cover"
      />
    </div>
  );
}
