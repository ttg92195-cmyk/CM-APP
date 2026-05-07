import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class MovieListTile extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const MovieListTile({
    super.key,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 55,
          height: 80,
          child: movie.fullPosterUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: movie.fullPosterUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.movie,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.movie,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
        ),
      ),
      title: Text(
        movie.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (movie.rating != null && movie.rating!.isNotEmpty) ...[
              Icon(Icons.star, size: 14, color: Colors.amber),
              const SizedBox(width: 2),
              Text(
                movie.rating!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (movie.year != null && movie.year!.isNotEmpty) ...[
              Text(
                movie.year!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (movie.resolution != null && movie.resolution!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  movie.resolution!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }
}
