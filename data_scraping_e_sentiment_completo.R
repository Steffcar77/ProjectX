#installation and loading of the necessary libraries
library(httr)
library(jsonlite)
library(writexl)
library(dplyr)
library(lubridate)
library(rvest)

#computing of the timestamp Unix for the period that goes from 2020 to 2024
start_date <- "2020-01-01"
end_date <- "2024-12-05"

#manual conversion
start_timestamp <- as.numeric(as.POSIXct(start_date, tz = "UTC"))
end_timestamp <- as.numeric(as.POSIXct(end_date, tz = "UTC"))

#printing the timestamp to see if they are correct
print(start_timestamp)
print(end_timestamp)

#generating of api credentials necessary to have access to reddit datas
#(after creating an app at the following link: https://www.reddit.com/prefs/apps/ to be recognized as developer)
client_id <- "_yPAqetiiTidZZwYEoTnIw"
client_secret <- "vUCaHPfXj9EPNuws0xoVrrd6ius7Mw"
user_agent <- "Project X Script by FuzzyItem6435"

#requesting the authorization 
response <- POST("https://www.reddit.com/api/v1/access_token",
                 authenticate(client_id, client_secret),
                 body = list(grant_type = "client_credentials"),
                 encode = "form")

#if the status code of the response just generated is 200 it means we gained the authorization
#we can now recive the access token
token <- content(response)$access_token

content_json <- content(response, as = "text", encoding = "UTF-8")
parsed_content <- fromJSON(content_json, flatten = TRUE)
print(parsed_content)

get_reddit_posts <- function(after = NULL, limit = 100) {
  url <- "https://oauth.reddit.com/r/all/search"
  query <- list(
    q = "TSLA",
    limit = limit,
    after = after,
    t = "all",
    before = end_timestamp,
    after = start_timestamp
  )
  
  # Effettua la richiesta GET
  response <- GET(url, add_headers(Authorization = paste("bearer", token)), query = query)
  content_type <- headers(response)$`content-type`
  
  if (grepl("application/json", content_type)) {
    # Parsing del JSON
    data <- content(response, as = "parsed", type = "application/json")
    posts <- data$data$children
    return(posts)
  } else if (grepl("text/html", content_type)) {
    # Parsing HTML (messaggio di errore o contenuto non previsto)
    warning("Ricevuto contenuto HTML. Ignorando questa risposta.")
    return(list())  # Restituisce una lista vuota per continuare
  } else {
    # Formato non supportato
    stop("Formato non supportato: ", content_type)
  }
}

# Ciclo principale per accumulare almeno 2000 post
all_posts <- list()
after <- NULL
post_count <- 0

while (post_count < 2000) {
  posts <- tryCatch(
    get_reddit_posts(after = after, limit = 100),
    error = function(e) {
      warning("Errore durante il recupero dei post: ", conditionMessage(e))
      return(list())  # Continua ignorando l'errore
    }
  )
  
  if (length(posts) == 0) break  # Termina se non ci sono più post validi
  
  all_posts <- c(all_posts, posts)  # Accumula i post
  post_count <- length(all_posts)  # Aggiorna il conteggio
  
  # Aggiorna 'after' per la paginazione
  after <- tryCatch(
    posts[[length(posts)]]$data$fullname,
    error = function(e) {
      warning("Errore durante l'accesso al fullname: ", conditionMessage(e))
      return(NULL)  # Continua ignorando l'errore
    }
  )
}

# Salvataggio su Excel
save_posts_to_excel <- function(all_posts, file_name = "reddit_posts.xlsx") {
  # Creazione del data frame
  post_data <- data.frame(
    Title = sapply(all_posts, function(p) p$data$title),
    Author = sapply(all_posts, function(p) p$data$author),
    Created_UTC = sapply(all_posts, function(p) p$data$created_utc),
    Selftext = sapply(all_posts, function(p) p$data$selftext), 
    Permalink = sapply(all_posts, function(p) paste0("https://reddit.com", p$data$permalink))
  )
  
  # Conversione timestamp in formato leggibile
  post_data$Created_UTC <- as.POSIXct(post_data$Created_UTC, origin = "1970-01-01", tz = "UTC")
  
  # Salvataggio su file Excel
  write_xlsx(post_data, file_name)
  
  message("File Excel creato: ", file_name)
}

save_posts_to_excel(all_posts, file_name = "reddit_posts.xlsx")

#############################################################################################################

library(tidyverse)
library(tidytext)
library(dplyr)
library(ggplot2)
library(readxl)  
library(stringr)
library(wordcloud2)
library(textstem)
library(igraph)
library(ggraph)
library(lubridate)
library(syuzhet)

my_stopwords <- c("a", "an", "the",        # Articoli
                  "and", "but", "or", "nor", "for", "yet", "so", # Congiunzioni
                  "in", "on", "at", "by", "to", "from", "with", "about", "as", "of", "for", "between", "under", "over", # Preposizioni
                  "he", "his", "she", "her", "it", "its", "they", "them", "their", "us", "we", "you", "your", "yours", "i", "me", "my", "mine", # Pronomi
                  "is", "are", "am", "was", "were", "be", "been", "being", # to be
                  "have", "has", "had", "having", # to have
                  "does", "do", "did", "doing",  # altri verbi ausiliari
                  "this", "that", "these", "those", "which", "who", "whom", "whose",  # Determinativi e pronomi relativi
                  "there", "here", "where", "how", "why", "what", "when", "who", # Avverbi interrogativi
                  "www", "jpg", "ta", "than", "too", "not", "will", "tsla", "com", "all", "just", "xb", "reddit", "redd", "webp", "pjpg", "https", "amp", "if", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z")

#file_path <- file.choose()
file_path <- "/Users/francescosantarelli/Documents/management_tools/TSLA_posts2.xlsx"
tesla_posts_selftext <- read_excel(file_path, sheet = "Sheet1")

tesla_posts_selftext <- tesla_posts_selftext %>%
  filter(!is.na(Selftext), Selftext != "")

tesla_posts_selftext <- tesla_posts_selftext %>%
  mutate(Selftext = str_replace_all(Selftext, "[[:punct:]]", " "),
         Selftext = str_replace_all(Selftext, "[0-9]", ""),
         Selftext = tolower(Selftext),
         Selftext = lemmatize_strings(Selftext))

clean_posts_selftext <- tesla_posts_selftext %>%
  select(Selftext) %>%
  unnest_tokens(word, Selftext) %>%
  filter(!word %in% my_stopwords)

# Top 15 parole
top_15_words_selftext <- clean_posts_selftext %>%
  count(word, sort = TRUE) %>%
  slice_max(n, n = 15, with_ties = FALSE)

top_15_words_selftext %>%
  ggplot(aes(x = reorder(word, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Words in Tesla Posts Selftext",
       x = "Words",
       y = "Frequency") +
  theme_minimal()

#top bigrams
top_15_bigrams_selftext<- tesla_posts_selftext %>%
  select(Selftext) %>% 
  unnest_tokens(bigram, Selftext, token = "ngrams", n = 2) %>% # Estrai i bigrammi
  separate(bigram, into = c("word1", "word2"), sep = " ") %>% # Dividi i bigrammi in due colonne
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>% # Rimuovi stop words
  unite(bigram, word1, word2, sep = " ") %>% # Ricompone i bigrammi
  count(bigram, sort = TRUE) %>% # Conta i bigrammi
  slice_max(n, n = 15, with_ties = FALSE)

top_15_bigrams_selftext%>%
  ggplot(aes(x = reorder(bigram, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Bigrams in Tesla Posts Selftext",
       x = "Bigrams",
       y = "Frequency") +
  theme_minimal()

#bigram net
biwords_df_selftext <- tesla_posts_selftext %>% select(Selftext) %>% unnest_tokens(output = bigram, input = Selftext, token = "ngrams", n = 2)

bigram_net_selftext <- biwords_df_selftext %>%
  separate(bigram,c( "word1", "word2"), sep = " ") %>%
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>%
  count(word1,word2, sort = TRUE) #non riunisce word1 e word2

bigram_net_selftext

bigram_igraph_selftext <- bigram_net_selftext %>%
  filter(n>75) %>% 
  graph_from_data_frame()
bigram_igraph_selftext

a_selftext <- grid::arrow(type = "closed", length = unit(.1, "inches"))
set.seed(7)
biplot_text_a_selftext = ggraph(bigram_igraph_selftext, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n), show.legend = FALSE,
                 arrow = a_selftext, end_cap = circle(.07, 'inches')) +
  geom_node_point(color = "#F06869", size = 5) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1, size = 3) +
  theme_void()

biplot_text_a_selftext

# Analisi del sentimento con Bing
sentiment_bing_selftext <- clean_posts_selftext %>%      
  inner_join(get_sentiments("bing")) %>% 
  count(sentiment, sort = TRUE)
print(sentiment_bing_selftext)

# Analisi del sentimento con AFINN
sentiment_afinn_selftext <- clean_posts_selftext %>%
  inner_join(get_sentiments("afinn")) %>%
  group_by(word) %>% 
  summarise(total_score = sum(value)) %>% 
  arrange(desc(total_score))
print(sentiment_afinn_selftext)

# Analisi del sentimento con NRC
sentiment_nrc_selftext <- clean_posts_selftext %>%
  inner_join(get_sentiments("nrc")) %>%
  count(sentiment, sort = TRUE)
print(sentiment_nrc_selftext)

# Visualizzazioni
sentiment_bing_selftext %>%
  ggplot(aes(x = sentiment, y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  labs(title = "Sentiment Analysis of Selftext with Bing",
       x = "Sentiment",
       y = "Count") +
  theme_minimal()

sentiment_afinn_selftext %>%
  mutate(abs_score = abs(total_score)) %>% 
  arrange(desc(abs_score)) %>%            
  slice_head(n = 20) %>%                  
  ggplot(aes(x = reorder(word, total_score), y = total_score, fill = total_score)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Sentiment Analysis of Selftext with AFINN",
       x = "Words",
       y = "Total Sentiment Score") +
  theme_minimal()

sentiment_nrc_selftext %>%
  filter(!sentiment %in% c("positive", "negative")) %>%  # Esclude i sentimenti "positive" e "negative"
  ggplot(aes(x = reorder(sentiment, n), y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Emotion Analysis of Selftext with NRC",
       x = "Emotion",
       y = "Count") +
  theme_minimal()

wordcloud2(top_15_words_selftext, size = 0.5, color = "random-light", backgroundColor = "black")

############################################################################################################################
############################################################################################################################
############################################################################################################################
#analisi dei titoli

tesla_posts_title <- read_excel(file_path, sheet = "Sheet1")

tesla_posts_title <- tesla_posts_title %>%
  filter(!is.na(Title), Title != "")

tesla_posts_title <- tesla_posts_title %>%
  mutate(Title = str_replace_all(Title, "[[:punct:]]", " "),
         Title = str_replace_all(Title, "[0-9]", ""),
         Title = tolower(Title),
         Title = lemmatize_strings(Title))

clean_posts_title <- tesla_posts_title %>%
  select(Title) %>%
  unnest_tokens(word, Title) %>%
  filter(!word %in% my_stopwords)

# Top 15 parole
top_15_words_title <- clean_posts_title %>%
  count(word, sort = TRUE) %>%
  slice_max(n, n = 15, with_ties = FALSE)

top_15_words_title %>%
  ggplot(aes(x = reorder(word, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Words in Tesla Posts Title",
       x = "Words",
       y = "Frequency") +
  theme_minimal()

#top bigrams
top_15_bigrams_title <- tesla_posts_title %>%
  select(Title) %>% 
  unnest_tokens(bigram, Title, token = "ngrams", n = 2) %>% # Estrai i bigrammi
  separate(bigram, into = c("word1", "word2"), sep = " ") %>% # Dividi i bigrammi in due colonne
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>% # Rimuovi stop words
  unite(bigram, word1, word2, sep = " ") %>% # Ricompone i bigrammi
  count(bigram, sort = TRUE) %>% # Conta i bigrammi
  slice_max(n, n = 15, with_ties = FALSE)

top_15_bigrams_title %>%
  ggplot(aes(x = reorder(bigram, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Bigrams in Tesla Posts Title",
       x = "Bigrams",
       y = "Frequency") +
  theme_minimal()

#bigram net_title

biwords_df_title <- tesla_posts_title %>% select(Title) %>% unnest_tokens(output = bigram, input = Title, token = "ngrams", n = 2)

bigram_net_title <- biwords_df_title %>%
  separate(bigram,c( "word1", "word2"), sep = " ") %>%
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>%
  count(word1,word2, sort = TRUE) #non riunisce word1 e word2

bigram_net_title

bigram_igraph_title <- bigram_net_title %>%
  filter(n>25) %>% 
  graph_from_data_frame()
bigram_igraph_title

a_title <- grid::arrow(type = "closed", length = unit(.1, "inches"))
set.seed(7)
biplot_text_a_title = ggraph(bigram_igraph_title, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n), show.legend = FALSE,
                 arrow = a_title, end_cap = circle(.07, 'inches')) +
  geom_node_point(color = "#F06869", size = 5) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1, size = 3) +
  theme_void()

biplot_text_a_title

# Analisi del sentimento con Bing
sentiment_bing_title <- clean_posts_title %>%      
  inner_join(get_sentiments("bing")) %>% 
  count(sentiment, sort = TRUE)
print(sentiment_bing_title)

# Analisi del sentimento con AFINN
sentiment_afinn_title <- clean_posts_title %>%
  inner_join(get_sentiments("afinn")) %>%
  group_by(word) %>% 
  summarise(total_score = sum(value)) %>% 
  arrange(desc(total_score))
print(sentiment_afinn_title)

# Analisi del sentimento con NRC
sentiment_nrc_title <- clean_posts_title %>%
  inner_join(get_sentiments("nrc")) %>%
  count(sentiment, sort = TRUE)
print(sentiment_nrc_title)

# Visualizzazioni
sentiment_bing_title %>%
  ggplot(aes(x = sentiment, y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  labs(title = "Sentiment Analysis of Title with Bing",
       x = "Sentiment",
       y = "Count") +
  theme_minimal()

sentiment_afinn_title %>%
  mutate(abs_score = abs(total_score)) %>% 
  arrange(desc(abs_score)) %>%            
  slice_head(n = 20) %>%                  
  ggplot(aes(x = reorder(word, total_score), y = total_score, fill = total_score)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Sentiment Analysis of Title with AFINN",
       x = "Words",
       y = "Total Sentiment Score") +
  theme_minimal()

sentiment_nrc_title %>%
  filter(!sentiment %in% c("positive", "negative")) %>%  # Esclude i sentimenti "positive" e "negative"
  ggplot(aes(x = reorder(sentiment, n), y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Emotion Analysis of Title with NRC",
       x = "Emotion",
       y = "Count") +
  theme_minimal()

wordcloud2(top_15_words_title, size = 0.5, color = "random-light", backgroundColor = "black")

############################################################################################################################
############################################################################################################################
############################################################################################################################

tesla_posts_combined <- read_excel(file_path, sheet = "Sheet1")

tesla_posts_combined <- tesla_posts_combined %>%
  filter(!is.na(Selftext), Selftext != "")

tesla_posts_combined <- tesla_posts_combined %>% mutate(CombinedText = paste(Title, Selftext, sep = " "))

tesla_posts_combined <- tesla_posts_combined %>%
  mutate(CombinedText = str_replace_all(CombinedText, "[[:punct:]]", " "),
         CombinedText = str_replace_all(CombinedText, "[0-9]", ""),
         CombinedText = tolower(CombinedText),
         CombinedText = lemmatize_strings(CombinedText))

clean_posts_CombinedText <- tesla_posts_combined %>%
  select(CombinedText) %>%
  unnest_tokens(word, CombinedText) %>%
  filter(!word %in% my_stopwords)

# Top 15 parole
top_15_words_CombinedText <- clean_posts_CombinedText %>%
  count(word, sort = TRUE) %>%
  slice_max(n, n = 15, with_ties = FALSE)

top_15_words_CombinedText %>%
  ggplot(aes(x = reorder(word, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Words in Tesla Posts CombinedText",
       x = "Words",
       y = "Frequency") +
  theme_minimal()

#top bigrams
top_15_bigrams_CombinedText<- tesla_posts_combined %>%
  select(CombinedText) %>% 
  unnest_tokens(bigram, CombinedText, token = "ngrams", n = 2) %>% # Estrai i bigrammi
  separate(bigram, into = c("word1", "word2"), sep = " ") %>% # Dividi i bigrammi in due colonne
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>% # Rimuovi stop words
  unite(bigram, word1, word2, sep = " ") %>% # Ricompone i bigrammi
  count(bigram, sort = TRUE) %>% # Conta i bigrammi
  slice_max(n, n = 15, with_ties = FALSE)

top_15_bigrams_CombinedText%>%
  ggplot(aes(x = reorder(bigram, n), y = n, fill = n)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Top 15 Bigrams in Tesla Posts CombinedText",
       x = "Bigrams",
       y = "Frequency") +
  theme_minimal()

#bigram net
biwords_df_combined <- tesla_posts_combined %>% select(CombinedText) %>% unnest_tokens(output = bigram, input = CombinedText, token = "ngrams", n = 2)

bigram_net_combined <- biwords_df_combined %>%
  separate(bigram,c( "word1", "word2"), sep = " ") %>%
  filter(!is.na(word1) & !is.na(word2)) %>% # Filtra bigrammi con NA
  filter(!word1 %in% my_stopwords, !word2 %in% my_stopwords) %>%
  count(word1,word2, sort = TRUE) #non riunisce word1 e word2

bigram_net_combined

bigram_igraph_combined <- bigram_net_combined %>%
  filter(n>75) %>% 
  graph_from_data_frame()
bigram_igraph_combined

a_combined <- grid::arrow(type = "closed", length = unit(.1, "inches"))
set.seed(7)
biplot_text_a_combined = ggraph(bigram_igraph_combined, layout = "fr") +
  geom_edge_link(aes(edge_alpha = n), show.legend = FALSE,
                 arrow = a_combined, end_cap = circle(.07, 'inches')) +
  geom_node_point(color = "#F06869", size = 5) +
  geom_node_text(aes(label = name), vjust = 1, hjust = 1, size = 3) +
  theme_void()

biplot_text_a_combined

# Analisi del sentimento con Bing
sentiment_bing_CombinedText <- clean_posts_CombinedText %>%      
  inner_join(get_sentiments("bing")) %>% 
  count(sentiment, sort = TRUE)
print(sentiment_bing_CombinedText)

# Analisi del sentimento con AFINN
sentiment_afinn_CombinedText <- clean_posts_CombinedText %>%
  inner_join(get_sentiments("afinn")) %>%
  group_by(word) %>% 
  summarise(total_score = sum(value)) %>% 
  arrange(desc(total_score))
print(sentiment_afinn_CombinedText)

# Analisi del sentimento con NRC
sentiment_nrc_CombinedText <- clean_posts_CombinedText %>%
  inner_join(get_sentiments("nrc")) %>%
  count(sentiment, sort = TRUE)
print(sentiment_nrc_CombinedText)

# Visualizzazioni
sentiment_bing_CombinedText %>%
  ggplot(aes(x = sentiment, y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  labs(title = "Sentiment Analysis of CombinedText with Bing",
       x = "Sentiment",
       y = "Count") +
  theme_minimal()

sentiment_afinn_CombinedText %>%
  mutate(abs_score = abs(total_score)) %>% 
  arrange(desc(abs_score)) %>%            
  slice_head(n = 20) %>%                  
  ggplot(aes(x = reorder(word, total_score), y = total_score, fill = total_score)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Sentiment Analysis of CombinedText with AFINN",
       x = "Words",
       y = "Total Sentiment Score") +
  theme_minimal()

sentiment_nrc_CombinedText %>%
  filter(!sentiment %in% c("positive", "negative")) %>%  # Esclude i sentimenti "positive" e "negative"
  ggplot(aes(x = reorder(sentiment, n), y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Emotion Analysis of CombinedText with NRC",
       x = "Emotion",
       y = "Count") +
  theme_minimal()

wordcloud2(top_15_words_CombinedText, size = 0.5, color = "random-light", backgroundColor = "black")

############################################################################################################################
############################################################################################################################
############################################################################################################################

tesla_posts_temporal <- readxl::read_excel(file_path)

# Fusione delle colonne Title e Selftext
tesla_posts_temporal <- tesla_posts_temporal %>%
  mutate(Content = paste(Title, Selftext, sep = " ")) %>%
  select(Content, Created_UTC)  # Consideriamo solo testo e data

# Rimozione valori NA
tesla_posts_temporal <- tesla_posts_temporal %>% filter(!is.na(Content), !is.na(Created_UTC))

# Calcolo del sentiment usando syuzhet
tesla_posts_temporal <- tesla_posts_temporal %>%
  mutate(sentiment = get_sentiment(Content, method = "syuzhet"))

# Conversione della data in formato Date (se necessario)
tesla_posts_temporal <- tesla_posts_temporal %>%
  mutate(Date = as.Date(Created_UTC))

# Aggregazione del sentiment per giorno
sentiment_over_time <- tesla_posts_temporal %>%
  group_by(Date) %>%
  summarise(avg_sentiment = mean(sentiment, na.rm = TRUE))

# Visualizzazione dell'andamento temporale del sentiment
ggplot(sentiment_over_time, aes(x = Date, y = avg_sentiment)) +
  geom_line(color = "blue") +
  labs(title = "Andamento temporale del Sentiment",
       x = "Data",
       y = "Sentiment Medio") + theme_minimal()

#andamento del sentiment diviso in positivo e negativo
tesla_posts_temporal <- readxl::read_excel(file_path) %>%
  mutate(Content = paste(Title, Selftext, sep = " ")) %>%
  select(Content, Created_UTC) %>%
  filter(!is.na(Content), !is.na(Created_UTC))

# Calcolo del sentiment positivo e negativo
tesla_posts_temporal <- tesla_posts_temporal %>%
  mutate(
    sentiment_positive = get_sentiment(Content, method = "syuzhet") %>% pmax(0), # Solo valori positivi
    sentiment_negative = get_sentiment(Content, method = "syuzhet") %>% pmin(0) %>% abs(), # Solo valori negativi
    Date = as.Date(Created_UTC))

# Aggregazione per giorno
sentiment_over_time <- tesla_posts_temporal %>%
  group_by(Date) %>%
  summarise(avg_positive = mean(sentiment_positive, na.rm = TRUE),
            avg_negative = mean(sentiment_negative, na.rm = TRUE))

# Creazione del grafico
ggplot(sentiment_over_time) +
  geom_line(aes(x = Date, y = avg_positive, color = "Positive Sentiment"), size = 1) +
  geom_line(aes(x = Date, y = avg_negative, color = "Negative Sentiment"), size = 1) +
  scale_color_manual(values = c("Positive Sentiment" = "blue", "Negative Sentiment" = "red")) +
  labs(title = "Andamento temporale del Sentiment positivo e negativo",
       x = "Data", y = "Sentiment Medio", color = "Tipologia di Sentiment") + theme_minimal()

#end