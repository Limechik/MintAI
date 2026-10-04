#import "MAMarkdownRenderer.h"

// Временная метка на диапазонах инлайн-кода — последующие проходы
// (bold/italic/strikethrough/ссылки) должны их пропускать, иначе, например,
// "**" внутри `code**span**` было бы (неверно) превращено в жирный текст.
// Снимается перед тем, как готовая строка отдаётся наружу.
static NSString *const kMALockedAttributeName = @"MAMarkdownLocked";

typedef NS_OPTIONS(NSInteger, MAMarkdownFontStyle) {
	MAMarkdownFontStyleNone   = 0,
	MAMarkdownFontStyleBold   = 1 << 0,
	MAMarkdownFontStyleItalic = 1 << 1,
};

typedef NS_ENUM(NSInteger, MABlockType) {
	MABlockTypeParagraph,
	MABlockTypeHeader,
	MABlockTypeCode,
	MABlockTypeQuote,
	MABlockTypeUnorderedList,
	MABlockTypeOrderedList,
	MABlockTypeRule,
};

@interface MAMarkdownBlock : NSObject
@property (nonatomic, assign) MABlockType type;
@property (nonatomic, assign) NSInteger headerLevel;   // только для Header (1…6)
@property (nonatomic, copy) NSString *text;            // Paragraph/Header/Code/Quote
@property (nonatomic, strong) NSArray *listItems;      // только для списков
@end

@implementation MAMarkdownBlock
@end

@implementation MAMarkdownRenderer

#pragma mark - Публичный вход

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
                                             baseFont:(UIFont *)baseFont
                                            textColor:(UIColor *)textColor {
	if (markdown.length == 0) {
		return [[NSAttributedString alloc] init];
	}

	NSArray *blocks = [self blocksFromMarkdown:markdown];
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

	for (MAMarkdownBlock *block in blocks) {
		NSAttributedString *rendered = [self attributedStringForBlock:block baseFont:baseFont textColor:textColor];
		if (rendered.length == 0) continue;

		if (result.length > 0) {
			// Пустая строка между блоками — визуальный отступ между
			// абзацем/заголовком/списком/цитатой/кодом.
			[result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n"
			                                                              attributes:@{NSFontAttributeName: baseFont}]];
		}
		[result appendAttributedString:rendered];
	}

	[result removeAttribute:kMALockedAttributeName range:NSMakeRange(0, result.length)];
	return result;
}

#pragma mark - Разбор на блоки

+ (NSArray *)blocksFromMarkdown:(NSString *)markdown {
	NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
	NSMutableArray *blocks = [NSMutableArray array];

	NSInteger count = (NSInteger)lines.count;
	NSInteger i = 0;

	while (i < count) {
		NSString *line = lines[i];

		if ([self isBlankLine:line]) {
			i++;
			continue;
		}

		// ```[язык]\n…\n``` — блок кода. Если модель не закрыла тройную
		// кавычку (обрыв стрима), забираем всё до конца текста.
		if ([self isCodeFenceLine:line]) {
			i++;
			NSMutableArray *codeLines = [NSMutableArray array];
			while (i < count && ![self isCodeFenceLine:lines[i]]) {
				[codeLines addObject:lines[i]];
				i++;
			}
			if (i < count) i++; // закрывающая ```

			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeCode;
			block.text = [codeLines componentsJoinedByString:@"\n"];
			[blocks addObject:block];
			continue;
		}

		NSInteger headerLevel = [self headerLevelForLine:line];
		if (headerLevel > 0) {
			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeHeader;
			block.headerLevel = headerLevel;
			block.text = [self headerTextForLine:line level:headerLevel];
			[blocks addObject:block];
			i++;
			continue;
		}

		if ([self isHorizontalRuleLine:line]) {
			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeRule;
			[blocks addObject:block];
			i++;
			continue;
		}

		if ([self isQuoteLine:line]) {
			NSMutableArray *quoteLines = [NSMutableArray array];
			while (i < count && [self isQuoteLine:lines[i]]) {
				[quoteLines addObject:[self quoteTextForLine:lines[i]]];
				i++;
			}
			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeQuote;
			block.text = [quoteLines componentsJoinedByString:@"\n"];
			[blocks addObject:block];
			continue;
		}

		if ([self isUnorderedListLine:line]) {
			NSMutableArray *items = [NSMutableArray array];
			while (i < count && [self isUnorderedListLine:lines[i]]) {
				[items addObject:[self unorderedListItemTextForLine:lines[i]]];
				i++;
			}
			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeUnorderedList;
			block.listItems = items;
			[blocks addObject:block];
			continue;
		}

		if ([self isOrderedListLine:line]) {
			NSMutableArray *items = [NSMutableArray array];
			while (i < count && [self isOrderedListLine:lines[i]]) {
				[items addObject:[self orderedListItemTextForLine:lines[i]]];
				i++;
			}
			MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
			block.type = MABlockTypeOrderedList;
			block.listItems = items;
			[blocks addObject:block];
			continue;
		}

		// Обычный абзац: склеиваем подряд идущие "простые" строки в один
		// блок, перенос строки внутри абзаца остаётся как есть.
		NSMutableArray *paragraphLines = [NSMutableArray array];
		while (i < count &&
		       ![self isBlankLine:lines[i]] &&
		       ![self isCodeFenceLine:lines[i]] &&
		       [self headerLevelForLine:lines[i]] == 0 &&
		       ![self isHorizontalRuleLine:lines[i]] &&
		       ![self isQuoteLine:lines[i]] &&
		       ![self isUnorderedListLine:lines[i]] &&
		       ![self isOrderedListLine:lines[i]]) {
			[paragraphLines addObject:lines[i]];
			i++;
		}
		MAMarkdownBlock *block = [[MAMarkdownBlock alloc] init];
		block.type = MABlockTypeParagraph;
		block.text = [paragraphLines componentsJoinedByString:@"\n"];
		[blocks addObject:block];
	}

	return blocks;
}

#pragma mark - Определение типа строки

+ (BOOL)isBlankLine:(NSString *)line {
	return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0;
}

+ (BOOL)isCodeFenceLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return [trimmed hasPrefix:@"```"];
}

+ (BOOL)isDigitChar:(unichar)c {
	return (c >= '0' && c <= '9');
}

+ (NSInteger)headerLevelForLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger length = trimmed.length;
	NSUInteger level = 0;
	while (level < length && [trimmed characterAtIndex:level] == '#') {
		level++;
	}
	if (level == 0 || level > 6) return 0;
	// После решёток обязателен пробел — иначе это не заголовок (например, хэштег).
	if (level >= length || [trimmed characterAtIndex:level] != ' ') return 0;
	return (NSInteger)level;
}

+ (NSString *)headerTextForLine:(NSString *)line level:(NSInteger)level {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSString *rest = [trimmed substringFromIndex:(NSUInteger)(level + 1)];
	return [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (BOOL)isHorizontalRuleLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (trimmed.length < 3) return NO;
	unichar first = [trimmed characterAtIndex:0];
	if (first != '-' && first != '*' && first != '_') return NO;
	for (NSUInteger idx = 0; idx < trimmed.length; idx++) {
		if ([trimmed characterAtIndex:idx] != first) return NO;
	}
	return YES;
}

+ (BOOL)isQuoteLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return [trimmed hasPrefix:@">"];
}

+ (NSString *)quoteTextForLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	trimmed = [trimmed substringFromIndex:1];
	if ([trimmed hasPrefix:@" "]) trimmed = [trimmed substringFromIndex:1];
	return trimmed;
}

+ (BOOL)isUnorderedListLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if (trimmed.length < 2) return NO;
	unichar first = [trimmed characterAtIndex:0];
	if (first != '-' && first != '*' && first != '+') return NO;
	return [trimmed characterAtIndex:1] == ' ';
}

+ (NSString *)unorderedListItemTextForLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return [[trimmed substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (BOOL)isOrderedListLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger length = trimmed.length;
	NSUInteger idx = 0;
	while (idx < length && [self isDigitChar:[trimmed characterAtIndex:idx]]) idx++;
	if (idx == 0 || idx >= length) return NO;
	if ([trimmed characterAtIndex:idx] != '.') return NO;
	idx++;
	return (idx < length && [trimmed characterAtIndex:idx] == ' ');
}

+ (NSString *)orderedListItemTextForLine:(NSString *)line {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger length = trimmed.length;
	NSUInteger idx = 0;
	while (idx < length && [self isDigitChar:[trimmed characterAtIndex:idx]]) idx++;
	idx++; // точка
	NSString *rest = [trimmed substringFromIndex:idx];
	return [rest stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - Рендер блока

+ (NSAttributedString *)attributedStringForBlock:(MAMarkdownBlock *)block
                                         baseFont:(UIFont *)baseFont
                                        textColor:(UIColor *)textColor {
	switch (block.type) {
		case MABlockTypeHeader:
			return [self attributedStringForHeader:block baseFont:baseFont textColor:textColor];
		case MABlockTypeCode:
			return [self attributedStringForCode:block baseFont:baseFont textColor:textColor];
		case MABlockTypeQuote:
			return [self attributedStringForQuote:block baseFont:baseFont textColor:textColor];
		case MABlockTypeUnorderedList:
			return [self attributedStringForList:block ordered:NO baseFont:baseFont textColor:textColor];
		case MABlockTypeOrderedList:
			return [self attributedStringForList:block ordered:YES baseFont:baseFont textColor:textColor];
		case MABlockTypeRule:
			return [self attributedStringForRuleWithFont:baseFont textColor:textColor];
		case MABlockTypeParagraph:
		default:
			return [self inlineAttributedStringFromText:block.text baseFont:baseFont textColor:textColor];
	}
}

+ (NSAttributedString *)attributedStringForHeader:(MAMarkdownBlock *)block
                                          baseFont:(UIFont *)baseFont
                                         textColor:(UIColor *)textColor {
	// H1 — жирный +6pt, дальше на 1pt меньше за уровень, но не мельче
	// базового размера — заголовок не должен теряться в пузыре с обычным текстом.
	CGFloat extra = MAX((CGFloat)(6 - (block.headerLevel - 1)), (CGFloat)1);
	UIFont *headerFont = [self fontWithStyle:MAMarkdownFontStyleBold size:baseFont.pointSize + extra];
	return [self inlineAttributedStringFromText:block.text baseFont:headerFont textColor:textColor];
}

+ (NSAttributedString *)attributedStringForCode:(MAMarkdownBlock *)block
                                        baseFont:(UIFont *)baseFont
                                       textColor:(UIColor *)textColor {
	UIFont *codeFont = [self monospaceFontOfSize:baseFont.pointSize - 1];
	UIColor *codeBackground = [UIColor colorWithWhite:0.5 alpha:0.15];

	// UILabel красит NSBackgroundColorAttributeName по ширине текста в
	// каждой отдельной строке, а не по ширине всего блока — короткие строки
	// иначе давали бы "лесенку" из закрашенных прямоугольников разной
	// ширины. Подбиваем каждую строку пробелами до длины самой длинной,
	// тогда подсветка выстраивается в аккуратный прямоугольник.
	NSArray *lines = [block.text componentsSeparatedByString:@"\n"];
	NSUInteger maxLength = 0;
	for (NSString *line in lines) {
		maxLength = MAX(maxLength, line.length);
	}
	NSMutableArray *paddedLines = [NSMutableArray arrayWithCapacity:lines.count];
	for (NSString *line in lines) {
		NSString *padding = [@"" stringByPaddingToLength:(maxLength - line.length) withString:@" " startingAtIndex:0];
		[paddedLines addObject:[line stringByAppendingString:padding]];
	}
	NSString *paddedText = [paddedLines componentsJoinedByString:@"\n"];

	NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
	// В коде часто нет пробелов (длинные идентификаторы/URL) — переносим по
	// символу, чтобы строка не вылезала за пузырь целиком не разбитой.
	paragraphStyle.lineBreakMode = NSLineBreakByCharWrapping;

	return [[NSAttributedString alloc] initWithString:paddedText attributes:@{
		NSFontAttributeName: codeFont,
		NSForegroundColorAttributeName: textColor,
		NSBackgroundColorAttributeName: codeBackground,
		NSParagraphStyleAttributeName: paragraphStyle,
	}];
}

+ (NSAttributedString *)attributedStringForQuote:(MAMarkdownBlock *)block
                                         baseFont:(UIFont *)baseFont
                                        textColor:(UIColor *)textColor {
	UIFont *italicFont = [self fontWithStyle:MAMarkdownFontStyleItalic size:baseFont.pointSize];
	UIColor *quoteColor = [textColor colorWithAlphaComponent:0.65];
	NSMutableAttributedString *inner = [self inlineAttributedStringFromText:block.text baseFont:italicFont textColor:quoteColor];

	NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
	paragraphStyle.headIndent = 12;
	paragraphStyle.firstLineHeadIndent = 12;
	[inner addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, inner.length)];
	return inner;
}

+ (NSAttributedString *)attributedStringForList:(MAMarkdownBlock *)block
                                        ordered:(BOOL)ordered
                                       baseFont:(UIFont *)baseFont
                                      textColor:(UIColor *)textColor {
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
	NSInteger number = 1;

	for (NSInteger idx = 0; idx < (NSInteger)block.listItems.count; idx++) {
		NSString *itemText = block.listItems[idx];
		NSString *markerText = ordered ? [NSString stringWithFormat:@"%ld.  ", (long)number] : @"•  ";
		number++;

		NSAttributedString *markerAttr = [[NSAttributedString alloc] initWithString:markerText
		                                                                  attributes:@{NSFontAttributeName: baseFont,
		                                                                               NSForegroundColorAttributeName: textColor}];
		NSAttributedString *itemAttr = [self inlineAttributedStringFromText:itemText baseFont:baseFont textColor:textColor];

		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		[line appendAttributedString:markerAttr];
		[line appendAttributedString:itemAttr];

		// Висячий отступ: если пункт списка перенёсся на вторую строку, она
		// выравнивается под текст, а не "наезжает" на маркер.
		NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		paragraphStyle.headIndent = markerAttr.size.width;
		[line addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, line.length)];

		if (idx > 0) {
			[result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"
			                                                              attributes:@{NSFontAttributeName: baseFont}]];
		}
		[result appendAttributedString:line];
	}

	return result;
}

+ (NSAttributedString *)attributedStringForRuleWithFont:(UIFont *)baseFont textColor:(UIColor *)textColor {
	// Текстовая имитация линии — настоящую пришлось бы рисовать отдельным
	// UIView, а пузырь сообщения — это простой UILabel без подвидов.
	NSString *ruleText = [@"" stringByPaddingToLength:24 withString:@"─" startingAtIndex:0];
	return [[NSAttributedString alloc] initWithString:ruleText attributes:@{
		NSFontAttributeName: [UIFont systemFontOfSize:baseFont.pointSize],
		NSForegroundColorAttributeName: [textColor colorWithAlphaComponent:0.35],
	}];
}

#pragma mark - Инлайн-разбор (жирный/курсив/код/зачёркнутый/ссылки)

+ (NSMutableAttributedString *)inlineAttributedStringFromText:(NSString *)text
                                                       baseFont:(UIFont *)baseFont
                                                      textColor:(UIColor *)textColor {
	NSMutableAttributedString *result =
		[[NSMutableAttributedString alloc] initWithString:text
		                                        attributes:@{NSFontAttributeName: baseFont,
		                                                     NSForegroundColorAttributeName: textColor}];

	// Инлайн-код — первым, чтобь его содержимое не трогали остальные проходы.
	[self applyCodeSpansToAttributedString:result baseFont:baseFont];

	[self applyPattern:@"\\*\\*\\*(.+?)\\*\\*\\*|___(.+?)___"
	toAttributedString:result
	        usingBlock:^(NSRange innerRange) {
		[self addStyle:(MAMarkdownFontStyleBold | MAMarkdownFontStyleItalic) toRange:innerRange inAttributedString:result];
	}];

	[self applyPattern:@"\\*\\*(.+?)\\*\\*|__(.+?)__"
	toAttributedString:result
	        usingBlock:^(NSRange innerRange) {
		[self addStyle:MAMarkdownFontStyleBold toRange:innerRange inAttributedString:result];
	}];

	[self applyPattern:@"\\*(.+?)\\*|(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])"
	toAttributedString:result
	        usingBlock:^(NSRange innerRange) {
		[self addStyle:MAMarkdownFontStyleItalic toRange:innerRange inAttributedString:result];
	}];

	[self applyPattern:@"~~(.+?)~~"
	toAttributedString:result
	        usingBlock:^(NSRange innerRange) {
		[result addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:innerRange];
	}];

	[self applyLinksToAttributedString:result];

	return result;
}

// Заменяет каждое совпадение pattern на его первую непустую захваченную
// группу (тем самым "съедая" маркеры вроде ** или __) и зовёт block с
// диапазоном, куда легла эта группа в итоговой строке — раскрашивать/менять
// шрифт там дальше должен сам block.
+ (void)applyPattern:(NSString *)pattern
  toAttributedString:(NSMutableAttributedString *)attributedString
          usingBlock:(void (^)(NSRange innerRange))block {
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
	if (!regex) return;

	NSString *string = attributedString.string;
	NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];

	// Обрабатываем справа налево: замена в конце строки не сдвигает индексы
	// ещё не обработанных совпадений левее неё.
	for (NSInteger idx = (NSInteger)matches.count - 1; idx >= 0; idx--) {
		NSTextCheckingResult *match = matches[idx];
		NSRange matchRange = match.range;

		if ([self rangeIsLocked:matchRange inAttributedString:attributedString]) continue;

		NSRange innerRange = NSMakeRange(NSNotFound, 0);
		for (NSUInteger g = 1; g < match.numberOfRanges; g++) {
			NSRange candidate = [match rangeAtIndex:g];
			if (candidate.location != NSNotFound) {
				innerRange = candidate;
				break;
			}
		}
		if (innerRange.location == NSNotFound) continue;

		NSString *innerText = [string substringWithRange:innerRange];
		NSDictionary *baseAttributes = [attributedString attributesAtIndex:matchRange.location effectiveRange:NULL];
		NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:innerText attributes:baseAttributes];
		[attributedString replaceCharactersInRange:matchRange withAttributedString:replacement];

		block(NSMakeRange(matchRange.location, innerText.length));
	}
}

+ (void)applyCodeSpansToAttributedString:(NSMutableAttributedString *)attributedString baseFont:(UIFont *)baseFont {
	UIFont *codeFont = [self monospaceFontOfSize:baseFont.pointSize - 1];
	UIColor *codeBackground = [UIColor colorWithWhite:0.5 alpha:0.15];

	[self applyPattern:@"`([^`\\n]+)`"
	toAttributedString:attributedString
	        usingBlock:^(NSRange innerRange) {
		[attributedString addAttribute:NSFontAttributeName value:codeFont range:innerRange];
		[attributedString addAttribute:NSBackgroundColorAttributeName value:codeBackground range:innerRange];
		[attributedString addAttribute:kMALockedAttributeName value:@YES range:innerRange];
	}];
}

+ (void)applyLinksToAttributedString:(NSMutableAttributedString *)attributedString {
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^)]+)\\)"
	                                                                        options:0
	                                                                          error:&error];
	if (!regex) return;

	NSString *string = attributedString.string;
	NSArray *matches = [regex matchesInString:string options:0 range:NSMakeRange(0, string.length)];

	for (NSInteger idx = (NSInteger)matches.count - 1; idx >= 0; idx--) {
		NSTextCheckingResult *match = matches[idx];
		NSRange matchRange = match.range;
		if ([self rangeIsLocked:matchRange inAttributedString:attributedString]) continue;

		NSRange textRange = [match rangeAtIndex:1];
		if (textRange.location == NSNotFound) continue;
		NSString *linkText = [string substringWithRange:textRange];

		NSDictionary *baseAttributes = [attributedString attributesAtIndex:matchRange.location effectiveRange:NULL];
		NSMutableDictionary *linkAttributes = [baseAttributes mutableCopy];
		linkAttributes[NSForegroundColorAttributeName] = [UIColor colorWithRed:0.20 green:0.45 blue:0.90 alpha:1.0];
		linkAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);

		NSAttributedString *replacement = [[NSAttributedString alloc] initWithString:linkText attributes:linkAttributes];
		[attributedString replaceCharactersInRange:matchRange withAttributedString:replacement];
	}
}

+ (BOOL)rangeIsLocked:(NSRange)range inAttributedString:(NSAttributedString *)attributedString {
	if (range.length == 0 || NSMaxRange(range) > attributedString.length) return NO;

	__block BOOL locked = NO;
	[attributedString enumerateAttribute:kMALockedAttributeName
	                              inRange:range
	                              options:0
	                           usingBlock:^(id value, NSRange r, BOOL *stop) {
		if ([value boolValue]) {
			locked = YES;
			*stop = YES;
		}
	}];
	return locked;
}

#pragma mark - Шрифты

// UIFontDescriptor (комбинирование "жирный"+"курсив" по маскам traits)
// появился только в iOS 7 — на iOS 6.1 SDK его нет. Вместо этого держим
// фиксированное семейство Helvetica с явными именами начертаний и сами
// отслеживаем текущий стиль по уже применённому шрифту (см. -styleOfFont:).
+ (void)addStyle:(MAMarkdownFontStyle)styleToAdd
         toRange:(NSRange)range
inAttributedString:(NSMutableAttributedString *)attributedString {
	UIFont *currentFont = [attributedString attribute:NSFontAttributeName atIndex:range.location effectiveRange:NULL];
	CGFloat size = currentFont ? currentFont.pointSize : 15;
	MAMarkdownFontStyle combinedStyle = [self styleOfFont:currentFont] | styleToAdd;
	UIFont *newFont = [self fontWithStyle:combinedStyle size:size];
	[attributedString addAttribute:NSFontAttributeName value:newFont range:range];
}

+ (MAMarkdownFontStyle)styleOfFont:(UIFont *)font {
	MAMarkdownFontStyle style = MAMarkdownFontStyleNone;
	NSString *name = font.fontName;
	if ([name rangeOfString:@"Bold"].location != NSNotFound) style |= MAMarkdownFontStyleBold;
	if ([name rangeOfString:@"Oblique"].location != NSNotFound ||
	    [name rangeOfString:@"Italic"].location != NSNotFound) {
		style |= MAMarkdownFontStyleItalic;
	}
	return style;
}

+ (UIFont *)fontWithStyle:(MAMarkdownFontStyle)style size:(CGFloat)size {
	BOOL bold = (style & MAMarkdownFontStyleBold) != 0;
	BOOL italic = (style & MAMarkdownFontStyleItalic) != 0;

	NSString *fontName;
	if (bold && italic) {
		fontName = @"Helvetica-BoldOblique";
	} else if (bold) {
		fontName = @"Helvetica-Bold";
	} else if (italic) {
		fontName = @"Helvetica-Oblique";
	} else {
		fontName = @"Helvetica";
	}

	UIFont *font = [UIFont fontWithName:fontName size:size];
	return font ?: [UIFont systemFontOfSize:size];
}

+ (UIFont *)monospaceFontOfSize:(CGFloat)size {
	UIFont *menlo = [UIFont fontWithName:@"Menlo-Regular" size:size];
	return menlo ?: [UIFont fontWithName:@"Courier" size:size];
}

@end
