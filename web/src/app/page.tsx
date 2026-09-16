import Image from "next/image";

const DOWNLOAD_WIN = "/downloads/RightClickNinja-Setup-1.0.0.exe";
const DOWNLOAD_MAC = "/downloads/RightClickNinja-Mac.pkg";

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
              Everyday Finder and Explorer tools that stay out of your way.
              Date Shift and screenshots are ready today. More are on the way.
            </p>

            <div className="cta-row">
              <a className="btn btn-primary" href={DOWNLOAD_MAC}>
                Download for Mac
              </a>
              <a className="btn btn-ghost" href={DOWNLOAD_WIN}>
                Download for Windows
              </a>
            </div>
            <p className="meta">
              Free · macOS 14+ · Windows 10 and 11 · Installer, about 10–20 MB
            </p>
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
            Select files, open the right-click menu, and launch Right Click
            Ninja. No separate workflow to learn.
          </p>
          <div className="steps">
            <div className="step">
              <div>
                <h3>Install once</h3>
                <p>
                  Mac: run the package into Applications. Windows: run setup
                  and optionally wire Explorer.
                </p>
              </div>
            </div>
            <div className="step">
              <div>
                <h3>Select files</h3>
                <p>
                  Grab one file or a whole stack. Multi-select is built for
                  batch work. Drag-and-drop works too.
                </p>
              </div>
            </div>
            <div className="step">
              <div>
                <h3>Right-click → Right Click Ninja</h3>
                <p>
                  Mac: Services → Date Shift with Right Click Ninja (enable it
                  once under Keyboard Shortcuts › Services if it is missing).
                  Windows 11: Show more options → Right Click Ninja. Then dial
                  the offset and apply.
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
                <li>
                  Finder / Explorer dates and embedded Date taken for photos
                  and video
                </li>
                <li>Negative offsets move earlier; positive move later</li>
                <li>Powered by ExifTool under the hood for media metadata</li>
              </ul>
            </div>
          </div>
        </section>

        <section className="section" id="screenshot">
          <div className="feature">
            <div>
              <h2>Screenshot</h2>
              <p>
                Print Screen for Mac, built in. Capture a region or the full
                display, then copy, save, or mark it up — the same Blue Shot
                workflow, from the Right Click Ninja menu bar.
              </p>
            </div>
            <div className="feature-panel">
              <ul>
                <li>Print Screen / F13, or Control-Shift-Command-4</li>
                <li>Copy to clipboard, Desktop, Save As, or the annotation editor</li>
                <li>Mac only — Windows already has a Print Screen key</li>
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
