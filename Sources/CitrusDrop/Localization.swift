import Foundation

enum L {
    static var english: Bool {
        get { UserDefaults.standard.string(forKey: "language") == "en" }
        set { UserDefaults.standard.set(newValue ? "en" : "ru", forKey: "language") }
    }
    static func t(_ ru: String, _ en: String) -> String { english ? en : ru }
    static func operation(_ operation: Operation) -> String {
        if operation.id.hasPrefix("convert:") { return operation.title }
        return english ? ["reveal":"Show in Finder","copyPath":"Copy path","copy":"Copy files","duplicate":"Duplicate","move":"Move…","airdrop":"AirDrop","float":"Float preview","terminal":"Terminal","resize":"Resize","crop":"Crop","flip":"Flip horizontal","grayscale":"Grayscale","extract":"Extract archive","rotate":"Rotate 90°","compress":"Compress","strip":"Remove metadata","mergePDF":"Merge PDF","splitPDF":"Split PDF","pdfText":"Extract text","trim":"Trim","zip":"Create ZIP"][operation.id] ?? operation.title : operation.title
    }
    static func error(_ message: String) -> String {
        guard english else { return message }
        let translations: [(String,String)] = [
            ("Выберите хотя бы один файл.","Choose at least one file."), ("Файл недоступен:","File is unavailable:"),
            ("Этот тип файла пока не поддерживается.","This file type is not supported."), ("Конвертер не создал результат.","The converter did not produce a result."),
            ("Уже сохранено:","Already saved:"), ("Не удалось прочитать изображение.","Cannot read the image."), ("Пустое изображение.","Empty image."),
            ("Для анимированного изображения выберите конвертацию; инструменты не должны удалять кадры.","Choose conversion for animated images; editing tools must not discard frames."),
            ("Установите FFmpeg для этого формата.","Install FFmpeg to use this format."), ("Не удалось декодировать изображение.","Cannot decode the image."),
            ("Не хватает памяти для поворота.","Not enough memory to rotate."), ("Не удалось повернуть изображение.","Cannot rotate the image."),
            ("Не удалось создать PDF.","Cannot create PDF."), ("Не удалось записать изображение.","Cannot write the image."),
            ("Нужен FFmpeg. Инструкция: меню → Зависимости.","FFmpeg is required. See Menu → Dependencies."),
            ("Повреждённый или закрытый PDF.","The PDF is damaged or locked."), ("Сначала снимите пароль с PDF.","Unlock the PDF first."),
            ("В PDF нет текстового слоя. OCR в этой версии не включён.","The PDF has no text layer. OCR is not included in this version."),
            ("PDF пуст или защищён.","The PDF is empty or locked."), ("Не удалось прочитать страницу PDF.","Cannot read a PDF page."),
            ("Недостаточно памяти для PDF.","Not enough memory for PDF."), ("Не удалось сохранить страницу.","Cannot save the page."),
            ("Ошибка сохранения страницы PDF.","Could not save a PDF page."), ("PDF недоступен:","PDF is unavailable:"),
            ("Не удалось добавить","Cannot add"), ("PDF недоступен.","PDF is unavailable."), ("Ошибка чтения PDF.","Could not read PDF."),
            ("Ошибка записи PDF.","Could not write PDF."), ("Для документов этого типа нужен бесплатный LibreOffice.","Install free LibreOffice for this document type."),
            ("LibreOffice не поддерживает эту пару форматов.","LibreOffice does not support this conversion."),
            ("В наборе есть одинаковые имена файлов.","The selection contains duplicate filenames."), ("Нет корректных таймкодов SRT/VTT.","No valid SRT/VTT timecodes found."),
            ("Формат ","Format "), (" недоступен в этой версии macOS."," is not available on this macOS version.")
        ]
        return translations.reduce(message) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
