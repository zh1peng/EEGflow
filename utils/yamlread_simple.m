function data = yamlread_simple(filename)
%YAMLREAD_SIMPLE Minimal YAML reader for simple config files.
% Supports:
%   - nested mappings via indentation (spaces)
%   - lists via "- " items
%   - scalars: numbers, strings, true/false, null, NaN
%   - inline lists like [1, 2, NaN]
%
% This is intentionally limited but sufficient for EEGdojo param templates.

    raw = fileread(filename);
    lines = regexp(raw, '\r\n|\n|\r', 'split');
    n = numel(lines);
    idx = 1;
    [data, ~] = parse_block(lines, idx, 0, n);
end

function [node, idx] = parse_block(lines, idx, indent, n)
    node = [];
    while idx <= n
        line = lines{idx};
        if is_comment_or_empty(line)
            idx = idx + 1;
            continue;
        end
        [lineIndent, text] = split_indent(line);
        if lineIndent < indent
            break;
        elseif lineIndent > indent && isempty(node)
            % Allow deeper indent if container not decided yet
            indent = lineIndent;
        elseif lineIndent > indent
            break;
        end

        if startsWith(text, '- ')
            if ~iscell(node)
                node = {};
            end
            [item, idx] = parse_list_item(lines, idx, lineIndent, n);
            node{end+1} = item; %#ok<AGROW>
        else
            if ~isstruct(node)
                node = struct();
            end
            [key, hasValue, value] = parse_key_value(text);
            if hasValue
                node.(key) = value;
                idx = idx + 1;
            else
                [child, idx] = parse_child(lines, idx + 1, lineIndent, n);
                node.(key) = child;
            end
        end
    end
end

function [item, idx] = parse_list_item(lines, idx, indent, n)
    line = lines{idx};
    [~, text] = split_indent(line);
    rest = strtrim(text(3:end)); % after "- "

    if isempty(rest)
        [item, idx] = parse_child(lines, idx + 1, indent, n);
        return;
    end

    if contains(rest, ':')
        [key, hasValue, value] = parse_key_value(rest);
        if hasValue
            item = struct();
            item.(key) = value;
            idx = idx + 1;
        else
            [child, idx] = parse_child(lines, idx + 1, indent, n);
            item = struct();
            item.(key) = child;
        end
    else
        item = parse_scalar(rest);
        idx = idx + 1;
    end
end

function [child, idx] = parse_child(lines, idx, parentIndent, n)
    % Find next non-empty line to determine child indent
    nextIdx = idx;
    while nextIdx <= n
        if ~is_comment_or_empty(lines{nextIdx})
            break;
        end
        nextIdx = nextIdx + 1;
    end
    if nextIdx > n
        child = struct();
        idx = nextIdx;
        return;
    end
    [childIndent, ~] = split_indent(lines{nextIdx});
    if childIndent <= parentIndent
        child = struct();
        idx = nextIdx;
        return;
    end
    [child, idx] = parse_block(lines, nextIdx, childIndent, n);
end

function [key, hasValue, value] = parse_key_value(text)
    tok = regexp(text, '^([^:]+):(.*)$', 'tokens', 'once');
    if isempty(tok)
        error('yamlread_simple:ParseError', 'Invalid line: %s', text);
    end
    key = strtrim(tok{1});
    rest = strtrim(tok{2});
    if isempty(rest)
        hasValue = false;
        value = [];
    else
        hasValue = true;
        value = parse_scalar(rest);
    end
end

function v = parse_scalar(text)
    text = strtrim(text);
    if isempty(text)
        v = '';
        return;
    end

    % Quoted strings
    if (startsWith(text, '"') && endsWith(text, '"')) || (startsWith(text, '''') && endsWith(text, ''''))
        v = text(2:end-1);
        return;
    end

    % Inline list
    if startsWith(text, '[') && endsWith(text, ']')
        v = parse_inline_list(text(2:end-1));
        return;
    end

    lowerText = lower(text);
    if any(strcmp(lowerText, {'null','~'}))
        v = [];
        return;
    elseif strcmp(lowerText, 'true')
        v = true;
        return;
    elseif strcmp(lowerText, 'false')
        v = false;
        return;
    elseif any(strcmp(lowerText, {'nan','.nan'}))
        v = NaN;
        return;
    elseif strcmp(text, '[]')
        v = [];
        return;
    end

    num = str2double(text);
    if ~isnan(num)
        v = num;
        return;
    end

    v = text;
end

function v = parse_inline_list(text)
    parts = split_list(text);
    items = cellfun(@parse_scalar, parts, 'UniformOutput', false);
    if all(cellfun(@(x) isnumeric(x) && isscalar(x), items))
        v = cell2mat(items);
    else
        v = items;
    end
end

function parts = split_list(text)
    text = strtrim(text);
    if isempty(text)
        parts = {};
        return;
    end

    parts = {};
    buf = '';
    inQuotes = false;
    quoteChar = '';
    for i = 1:numel(text)
        ch = text(i);
        if inQuotes
            if ch == quoteChar
                inQuotes = false;
            end
            buf(end+1) = ch; %#ok<AGROW>
            continue;
        end
        if ch == '"' || ch == ''''
            inQuotes = true;
            quoteChar = ch;
            buf(end+1) = ch; %#ok<AGROW>
            continue;
        end
        if ch == ','
            parts{end+1} = strtrim(buf); %#ok<AGROW>
            buf = '';
        else
            buf(end+1) = ch; %#ok<AGROW>
        end
    end
    if ~isempty(buf)
        parts{end+1} = strtrim(buf); %#ok<AGROW>
    end
end

function tf = is_comment_or_empty(line)
    tf = isempty(strtrim(line)) || startsWith(strtrim(line), '#');
end

function [indent, text] = split_indent(line)
    m = regexp(line, '^\s*', 'match', 'once');
    indent = numel(m);
    text = strtrim(line);
end
