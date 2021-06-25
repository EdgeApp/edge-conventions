const path = require('path')
const fs = require('fs')

const MAIN_HEADER = 'Edge Development Conventions'
const TOC_FILE_NAME = 'README.md'

const excludedArray = fs
  .readFileSync(path.join(process.cwd(), '.gitignore'))
  .toString()
  .split('\n')
  .filter(str => str && !str.includes('#'))
  .map(str => str.replace('/', ''))

const createFolderTree = (
  startPath = '.',
  include = '.md',
  excludes = excludedArray
) => {
  const result = { files: [], folders: {} }
  if (!fs.existsSync(startPath)) return result

  const filePaths = fs.readdirSync(startPath)

  for (const fileName of filePaths) {
    const fullFilePath = path.join(startPath, fileName)

    if (excludedArray.includes(fullFilePath)) continue

    if (fs.lstatSync(fullFilePath).isDirectory()) {
      const child = createFolderTree(fullFilePath, include, excludes)
      if (child.files.length > 0 || Object.keys(child.folders).length > 0) {
        result.folders[fileName] = child
      }
    }

    if (fullFilePath.indexOf(include) >= 0) {
      const dirname = startPath.substring(startPath.lastIndexOf('/') + 1)
      if (fileName.split('.')[0] !== dirname) result.files.push(fileName)
    }
  }

  return result
}

const createContentMap = (contentTree, startPath = '.') => {
  const { files = [], folders } = contentTree
  const content = []
  const result = { [startPath]: content }

  for (const file of files) {
    if (file === TOC_FILE_NAME) continue

    const markdownFile = fs.readFileSync(path.join(startPath, `${file}`))
    const title = markdownFile.toString().split('\n')[0].split(' &nbsp; ')[1]
    content.push({ indent: 0, file, title })
  }

  for (const folder in folders) {
    const subFolder = folders[folder]
    const subFolderPath = path.join(startPath, `${folder}`)
    const subFolderContent = createContentMap(subFolder, subFolderPath)

    Object.assign(result, subFolderContent)

    const folderNameContent = {
      indent: 0,
      file: path.join(folder, TOC_FILE_NAME),
      title: `${folder.charAt(0).toUpperCase() + folder.slice(1)}`
    }

    const adjFolderToc = subFolderContent[subFolderPath].map(fileContent => ({
      ...fileContent,
      file: `${folder}/${fileContent.file}`,
      indent: fileContent.indent + 1
    }))

    content.push(folderNameContent, ...adjFolderToc)
  }

  return result
}

const createContentMarkdown = contentMap => {
  const contentMarkdown = []

  for (const key in contentMap) {
    const dirname = key.split('/').pop()

    const header =
      dirname === '.'
        ? `# ${MAIN_HEADER}`
        : `# [<](../${TOC_FILE_NAME}) &nbsp; ${
            dirname.charAt(0).toUpperCase() + dirname.slice(1)
          } Conventions`

    const content = contentMap[key]
      .map(
        ({ indent = 0, title, file }) =>
          `${new Array(indent * 2).fill(' ').join('')}* [${title}](${file})\n`
      )
      .join('')

    contentMarkdown.push({
      path: `${key}/${TOC_FILE_NAME}`,
      data: `${header}${`\n\n## Table of Contents\n\n`}${content}`
    })
  }

  return contentMarkdown
}

const folderTree = createFolderTree()
const tocMap = createContentMap(folderTree)
const tocMarkdown = createContentMarkdown(tocMap)

tocMarkdown.forEach(({ path, data }) => fs.writeFileSync(path, data))
