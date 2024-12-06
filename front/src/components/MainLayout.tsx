import BackGround from "./Background";
import BackButton from "./BackButton";

export default async function MainLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <>
      <BackButton />
      <div className="w-full h-full flex flex-col items-center p-6 md:p-24 z-2">
        {children}
      </div>
      <BackGround />
    </>
  );
}
