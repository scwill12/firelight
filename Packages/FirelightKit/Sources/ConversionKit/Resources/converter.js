// Turns a MOBI or AZW3 into an EPUB, inside a hidden WKWebView.
//
// foliate-js does the hard part — parsing PalmDB, the MOBI headers and the
// KF8 sections — and JSZip writes the result. Everything here is the glue:
// pulling each section out as XHTML, collecting the images it references, and
// assembling a valid EPUB 3 package around them.

import { MOBI, isMOBI } from './mobi.js'

const XHTML = 'application/xhtml+xml'

const escapeXML = (value) =>
    String(value ?? '')
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&apos;')

const report = (stage, fraction) => {
    window.webkit?.messageHandlers?.progress?.postMessage({ stage, fraction })
}

/// Blob URLs are how foliate hands back resources; this turns one back into
/// bytes we can put in the zip.
const blobFromURL = async (url) => {
    const response = await fetch(url)
    return await response.blob()
}

const extensionForType = (type) => ({
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif',
    'image/webp': 'webp', 'image/svg+xml': 'svg',
}[type] ?? 'bin')

async function convert(bytes) {
    const file = new File([bytes], 'book.mobi')

    if (!(await isMOBI(file))) {
        throw new Error('NOT_MOBI')
    }

    report('parsing', 0)
    const book = await new MOBI({ unzlib: null }).open(file)

    const zip = new JSZip()
    // The mimetype entry must be first and stored uncompressed, or readers
    // reject the file.
    zip.file('mimetype', 'application/epub+zip', { compression: 'STORE' })
    zip.file('META-INF/container.xml',
        `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>`)

    const metadata = book.metadata ?? {}
    const title = metadata.title || 'Untitled'
    const author = Array.isArray(metadata.author)
        ? metadata.author.join(', ')
        : (metadata.author || '')
    const language = metadata.language || 'en'
    const identifier = metadata.identifier || `firelight-${Date.now()}`

    // Images are deduplicated by blob URL: a cover repeated on every chapter
    // should be one file, not forty.
    const resources = new Map()
    let resourceIndex = 0

    const serializer = new XMLSerializer()
    const sections = []

    for (let index = 0; index < book.sections.length; index++) {
        report('writing', index / Math.max(1, book.sections.length))

        const section = book.sections[index]
        let doc
        try {
            doc = await section.createDocument()
        } catch (error) {
            continue
        }

        for (const image of Array.from(doc.querySelectorAll('img[src], image[href]'))) {
            const attribute = image.hasAttribute('src') ? 'src' : 'href'
            const value = image.getAttribute(attribute)
            if (!value?.startsWith('blob:')) continue

            let entry = resources.get(value)
            if (!entry) {
                const blob = await blobFromURL(value)
                const name = `images/img${resourceIndex++}.${extensionForType(blob.type)}`
                entry = { name, type: blob.type || 'image/jpeg' }
                resources.set(value, entry)
                zip.file(`OEBPS/${name}`, await blob.arrayBuffer())
            }
            image.setAttribute(attribute, `../${entry.name}`)
        }

        const name = `text/section${index}.xhtml`
        const body = doc.body ? serializer.serializeToString(doc.body) : '<body/>'
        zip.file(`OEBPS/${name}`,
            `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="${escapeXML(language)}">
<head><meta charset="utf-8"/><title>${escapeXML(title)}</title></head>
${body}
</html>`)
        sections.push({ id: `s${index}`, href: name })
    }

    // The cover, when the book has one.
    let coverName = null
    try {
        const cover = await book.getCover?.()
        if (cover) {
            coverName = `images/cover.${extensionForType(cover.type)}`
            zip.file(`OEBPS/${coverName}`, await cover.arrayBuffer())
        }
    } catch (error) {
        // A missing cover is not a failed conversion.
    }

    report('writing', 1)

    const manifest = sections
        .map(s => `    <item id="${s.id}" href="${s.href}" media-type="${XHTML}"/>`)
        .concat([...resources.values()].map((r, i) =>
            `    <item id="img${i}" href="${r.name}" media-type="${r.type}"/>`))
        .concat(coverName
            ? [`    <item id="cover-image" href="${coverName}" media-type="image/jpeg" properties="cover-image"/>`]
            : [])
        .join('\n')

    const spine = sections.map(s => `    <itemref idref="${s.id}"/>`).join('\n')

    zip.file('OEBPS/content.opf',
        `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">${escapeXML(identifier)}</dc:identifier>
    <dc:title>${escapeXML(title)}</dc:title>
    <dc:language>${escapeXML(language)}</dc:language>
    ${author ? `<dc:creator>${escapeXML(author)}</dc:creator>` : ''}
    <meta property="dcterms:modified">${new Date().toISOString().replace(/\.\d+Z$/, 'Z')}</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="${XHTML}" properties="nav"/>
${manifest}
  </manifest>
  <spine>
${spine}
  </spine>
</package>`)

    const tocEntries = (book.toc?.length ? book.toc : sections.map((s, i) => ({
        label: `Section ${i + 1}`, href: s.href,
    })))
    const navItems = tocEntries.map((entry, i) => {
        // foliate's TOC hrefs point into its own addressing; map them back to
        // the section files we just wrote.
        let href = sections[Math.min(i, sections.length - 1)]?.href ?? sections[0]?.href
        try {
            const resolved = book.resolveHref?.(entry.href)
            if (resolved?.index != null && sections[resolved.index]) {
                href = sections[resolved.index].href
            }
        } catch (error) { /* fall back to order */ }
        return `      <li><a href="${href}">${escapeXML(entry.label ?? `Section ${i + 1}`)}</a></li>`
    }).join('\n')

    zip.file('OEBPS/nav.xhtml',
        `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><meta charset="utf-8"/><title>Contents</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>Contents</h1>
    <ol>
${navItems}
    </ol>
  </nav>
</body>
</html>`)

    report('validating', 1)
    if (!sections.length) throw new Error('NO_CONTENT')

    const output = await zip.generateAsync({ type: 'base64', compression: 'DEFLATE' })
    return { base64: output, title, author, sections: sections.length }
}

window.firelightConvert = async (base64) => {
    try {
        const binary = atob(base64)
        const bytes = new Uint8Array(binary.length)
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
        const result = await convert(bytes.buffer)
        window.webkit.messageHandlers.done.postMessage(result)
    } catch (error) {
        window.webkit.messageHandlers.failed.postMessage({
            reason: String(error?.message ?? error),
        })
    }
}

window.webkit?.messageHandlers?.ready?.postMessage({ ready: true })
