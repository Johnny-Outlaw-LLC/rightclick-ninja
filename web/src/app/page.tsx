import Image from "next/image";

const DOWNLOAD = "/downloads/RightClickNinja-Setup-1.0.0.exe";

export default function Home() {
  return (
    <>
      <div className="grain" aria-hidden />

      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="brand">
              <Image
                src="/images/rightclick-ninja.svg"
                alt=""
                width={64}
                height={64}
                priority
              />
              <div className="brand-name">Right Click Ninja</div>
            </div>

            <h1 className="headline">File fixes. One right-click.</h1>
            <p className="lede">
              Everyday Explorer tools that stay out of your way. Date Shift is
              ready today. More are on the way.
            </p>

            <div className="cta-row">
              <a className="btn btn-primary" href={DOWNLOAD}>
                Download for Windows
              </a>
              <a className="btn btn-ghost" href="#how">
                See how it works
              </a>
            </div>
            <p className="meta">Free installer · Windows 10 and 11 · About 10 MB</p>
          </div>

          <div className="hero-visual" aria-hidden>
            <Image
              src="/images/hero.png"
              alt=""
              fill
              priority
              sizes="(max-width: 900px) 100vw, 50vw"
              style={{ objectFit: "cover" }}
            />
          </div>
        </section>

        <section className="section" id="how">
          <h2>From the menu you already use</h2>
          <p>
            Select files in Explorer, open the classic right-click menu, and
            launch Right Click Ninja. No separate workflow to learn.
          </p>
          <div className="steps">
            <div className="step">
              <div>
                <h3>Install once</h3>
                <p>
                  Run the setup. It drops into your Start menu and can wire
                  itself into Explorer.
                </p>
              </div>
            </div>
            <div className="step">
              <div>
                <h3>Select files</h3>
                <p>
                  Grab one file or a whole stack. Multi-select is built for
                  batch work.
                </p>
              </div>
            </div>
            <div className="step">
              <div>
                <h3>Show more options → Right Click Ninja</h3>
                <p>
                  On Windows 11 that is the classic menu. Then dial the offset
                  and apply.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="section" id="date-shift">
          <div className="feature">
            <div>
              <h2>Date Shift</h2>
              <p>
                Nudge Created, Modified, Accessed, and embedded media dates
                forward or back by days, hours, or minutes. Live preview before
                you commit.
              </p>
            </div>
            <div className="feature-panel">
              <ul>
                <li>Explorer dates and embedded Date taken for photos and video</li>
                <li>Negative offsets move earlier; positive move later</li>
                <li>Powered by ExifTool under the hood for media metadata</li>
              </ul>
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <span>© {new Date().getFullYear()} Outlaw Apps · Johnny Outlaw LLC</span>
        <a href="https://www.outlawapps.online" target="_blank" rel="noreferrer">
          outlawapps.online
        </a>
      </footer>
    </>
  );
}
