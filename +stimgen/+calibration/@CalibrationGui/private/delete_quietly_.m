function delete_quietly_(ffn)
% Remove a temporary file. Never throws: this runs from an onCleanup, where
% an error would mask whatever ended the function that scheduled it.
try
    if isfile(ffn)
        delete(ffn);
    end
catch
end
end
