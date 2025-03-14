return {

    Generate = {
        prompt = "Generate the code of the following request: $input, only output the final code without additional quotes around it:\n$text",
        replace = true,
    },

    Chat = { prompt = "$input" },

    Summarize = {
        prompt = "Please provide a concise summary that captures key points without adding new information, here is the final text:\n$text",
    },

    Ask = { prompt = "Here is the code:\n```$filetype\n$text\n```\n\n My question is:\n$input,Always do not repeat the whole code, just create the needed code and tell the user where to add that code in their code file." },

    Enhance_Grammar_Spelling = {
        prompt = "Modify the following text to improve grammar and spelling, only output the final text without additional quotes around it:\n$text",
        replace = true,
    },

    Make_Concise = {
        prompt = "Modify the following text to make it as simple and concise as possible, only output the final text without additional quotes around it:\n$text",
        replace = true,
    },

    Review_Code = {
        prompt = "Please review and analyze this code:\n```$filetype\n$text\n```\n\n, identify potential issues and identify potential areas for improvement related to code smells, readability, maintainability, performance, security, etc. Do not list issues already addressed in the given code. Focus on providing up to 5 constructive suggestions that could make the code more robust, efficient, or align with best practices. For each suggestion, provide a brief explanation of the potential benefits. After listing any recommendations, summarize if you found notable opportunities to enhance the code quality overall or if the code generally follows sound design principles. If no issues found, simply reply with: there is no error in the code.",
    },

    Enhance_Code = {
        prompt = "Enhance the following code to improve its performance, readability, and efficiency:\n```$filetype\n$text\n```\n\n, always only output the enhanced result in the format of ```$filetype\n...\n```:\n```$filetype\n$text\n```",
        replace = true,
        extract = "```$filetype\n(.-)```",
    },

    Fix_Code = {
        prompt = "Please fix this code: \n```$filetype\n$text\n```\n\n, the error is:\n$input, Additionally specify why the error happend. Please format your response in a way that clearly highlights the issues and suggests possible fixes,Always do not repeat the whole code, just create the needed code and tell the user where to add that code in their code file.",
    },

    Change_Code = {

        prompt = "Change the following code:\n```$filetype\n$text\n```\n\n,according to these instructions:\n$input, Always Only output the final code without additional quotes around it:\n$text.",
        replace = true,
        extract = "```$filetype\n(.-)```",
    },

    Document_Code = {
        prompt = "Write a brief documentation comment for:\n```$filetype\n$text\n```\n\n, If documentation comments exist in the given code, use them as examples. Pay attention to the scope of the selected code (e.g. exported function/API vs implementation detail in a function), and use the idiomatic style for that type of code scope. Only generate the documentation for the selected code, do not generate the code itself again. Do not enclose any other code or comments besides the documentation. Enclose only the documentation for the given code and nothing else, the result should only be text and not a code.",
    },

    Explain_Code = {
        prompt = "Explain this code, so a noob programmer would understand the code, here is the code : \n```$filetype\n$text\n```\n\n,Always do not repeat the code, just the parts that you are explaining.",
    },
}
